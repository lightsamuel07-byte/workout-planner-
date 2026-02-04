#!/usr/bin/env python3
"""
Import workout history from Google Sheets into a local SQLite database.
"""

import argparse
import os
import re
import sys
from datetime import date, datetime, timedelta

import yaml


ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT_DIR not in sys.path:
    sys.path.insert(0, ROOT_DIR)

from src.sheets_reader import SheetsReader
from src.workout_db import WorkoutDB


DAY_NAME_TO_INDEX = {
    "monday": 0,
    "tuesday": 1,
    "wednesday": 2,
    "thursday": 3,
    "friday": 4,
    "saturday": 5,
    "sunday": 6,
}

DAY_PATTERN = re.compile(r"\b(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\b", re.IGNORECASE)
INLINE_DATE_PATTERN = re.compile(r"(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?")
SHEET_DATE_PATTERNS = [
    re.compile(r"Weekly Plan \((\d{1,2})/(\d{1,2})/(\d{4})\)"),
    re.compile(r"\(Weekly Plan\)\s*(\d{1,2})/(\d{1,2})/(\d{4})"),
]

RPE_PATTERNS = [
    re.compile(r"rpe\s*[:=]?\s*(\d+(?:\.\d+)?)", re.IGNORECASE),
    re.compile(r"@\s*(\d+(?:\.\d+)?)\s*rpe\b", re.IGNORECASE),
    re.compile(r"\b(\d+(?:\.\d+)?)\s*rpe\b", re.IGNORECASE),
]


def parse_args():
    parser = argparse.ArgumentParser(
        description="Import all weekly workout sheets into a local SQLite database."
    )
    parser.add_argument(
        "--config",
        default="config.yaml",
        help="Path to config.yaml (default: config.yaml)",
    )
    parser.add_argument(
        "--db-path",
        default="data/workout_history.db",
        help="Path to SQLite database file (default: data/workout_history.db)",
    )
    parser.add_argument(
        "--sheet",
        default=None,
        help="Optional single sheet name to import (default: import all weekly sheets)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Optional limit of most recent weekly sheets to import",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse and print stats without writing to the database",
    )
    parser.add_argument(
        "--service-account-file",
        default=None,
        help="Optional path to service account JSON (overrides config value)",
    )
    return parser.parse_args()


def safe_cell(row, index):
    if index < len(row):
        return str(row[index]).strip()
    return ""


def extract_day_name(text):
    if not text:
        return None
    match = DAY_PATTERN.search(text)
    if not match:
        return None
    return match.group(1).capitalize()


def parse_sheet_anchor_date(sheet_name):
    for pattern in SHEET_DATE_PATTERNS:
        match = pattern.match(sheet_name or "")
        if not match:
            continue
        month = int(match.group(1))
        day = int(match.group(2))
        year = int(match.group(3))
        try:
            return date(year, month, day)
        except ValueError:
            return None
    return None


def best_year_for_month_day(anchor_date, month, day):
    if not anchor_date:
        return datetime.now().year

    candidate_dates = []
    for year in [anchor_date.year - 1, anchor_date.year, anchor_date.year + 1]:
        try:
            candidate = date(year, month, day)
            candidate_dates.append(candidate)
        except ValueError:
            continue

    if not candidate_dates:
        return anchor_date.year

    nearest = min(candidate_dates, key=lambda d: abs((d - anchor_date).days))
    return nearest.year


def infer_date_from_anchor(anchor_date, day_name):
    if not anchor_date or not day_name:
        return None

    target_weekday = DAY_NAME_TO_INDEX.get(day_name.lower())
    if target_weekday is None:
        return None

    # Prefer the same calendar week starting from the anchor day.
    for offset in range(0, 7):
        candidate = anchor_date + timedelta(days=offset)
        if candidate.weekday() == target_weekday:
            return candidate

    # Fallback to previous week match if needed.
    for offset in range(1, 8):
        candidate = anchor_date - timedelta(days=offset)
        if candidate.weekday() == target_weekday:
            return candidate

    return None


def parse_session_date(day_label, day_name, sheet_anchor_date):
    match = INLINE_DATE_PATTERN.search(day_label or "")
    if match:
        month = int(match.group(1))
        day = int(match.group(2))
        year_token = match.group(3)
        if year_token:
            year = int(year_token)
            if year < 100:
                year += 2000
        else:
            year = best_year_for_month_day(sheet_anchor_date, month, day)

        try:
            return date(year, month, day)
        except ValueError:
            return None

    return infer_date_from_anchor(sheet_anchor_date, day_name)


def extract_rpe_value(text):
    if not text:
        return None

    for pattern in RPE_PATTERNS:
        match = pattern.search(text)
        if not match:
            continue
        value = float(match.group(1))
        if 1.0 <= value <= 10.0:
            return value
    return None


def looks_like_day_header(first_col, second_col):
    day_name = extract_day_name(first_col)
    if not day_name:
        return False

    # Day rows are usually standalone labels.
    if not second_col:
        return True

    # Be permissive for labels like "MONDAY - FORT" where col B is empty.
    if second_col.lower() in {"exercise", "block"}:
        return True

    return False


def parse_sessions_from_values(values, sheet_name):
    sheet_anchor_date = parse_sheet_anchor_date(sheet_name)
    sessions = []
    current_session = None

    for row_num, row in enumerate(values, start=1):
        if not row:
            continue

        first_col = safe_cell(row, 0)
        second_col = safe_cell(row, 1)

        if looks_like_day_header(first_col, second_col):
            day_name = extract_day_name(first_col)
            session_date = parse_session_date(first_col, day_name, sheet_anchor_date)

            current_session = {
                "sheet_name": sheet_name,
                "day_label": first_col,
                "day_name": day_name,
                "session_date": session_date.isoformat() if session_date else None,
                "entries": [],
            }
            sessions.append(current_session)
            continue

        if first_col.lower() in {"block", "rationale"}:
            continue
        if second_col.lower() == "exercise":
            continue
        if not current_session:
            continue
        if not second_col:
            continue

        prescribed_notes = safe_cell(row, 6)
        log_text = safe_cell(row, 7)
        combined_notes = " ".join(v for v in [log_text, prescribed_notes] if v).strip()
        parsed_rpe = extract_rpe_value(combined_notes)

        current_session["entries"].append(
            {
                "source_row": row_num,
                "block": first_col,
                "exercise_name": second_col,
                "prescribed_sets": safe_cell(row, 2),
                "prescribed_reps": safe_cell(row, 3),
                "prescribed_load": safe_cell(row, 4),
                "prescribed_rest": safe_cell(row, 5),
                "prescribed_notes": prescribed_notes,
                "log_text": log_text,
                "parsed_rpe": parsed_rpe,
                "parsed_notes": None,
            }
        )

    return sessions


def fetch_sheet_values(reader, spreadsheet_id, sheet_name):
    range_name = f"'{sheet_name}'!A:H"
    result = reader.service.spreadsheets().values().get(
        spreadsheetId=spreadsheet_id,
        range=range_name
    ).execute()
    return result.get("values", [])


def import_one_sheet(reader, db, spreadsheet_id, sheet_name, dry_run=False):
    values = fetch_sheet_values(reader, spreadsheet_id, sheet_name)
    sessions = parse_sessions_from_values(values, sheet_name)

    imported_sessions = 0
    imported_rows = 0
    imported_rpe_rows = 0

    if dry_run:
        for session in sessions:
            imported_sessions += 1
            imported_rows += len(session["entries"])
            imported_rpe_rows += sum(1 for entry in session["entries"] if entry["parsed_rpe"] is not None)
        return {
            "sessions": imported_sessions,
            "rows": imported_rows,
            "rows_with_rpe": imported_rpe_rows,
        }

    with db.transaction():
        for session in sessions:
            session_id = db.upsert_session(
                sheet_name=session["sheet_name"],
                day_label=session["day_label"],
                day_name=session["day_name"],
                session_date=session["session_date"],
            )
            imported_sessions += 1

            for entry in session["entries"]:
                exercise_id = db.upsert_exercise(entry["exercise_name"])
                db.upsert_exercise_log(
                    session_id=session_id,
                    exercise_id=exercise_id,
                    source_row=entry["source_row"],
                    block=entry["block"],
                    prescribed_sets=entry["prescribed_sets"],
                    prescribed_reps=entry["prescribed_reps"],
                    prescribed_load=entry["prescribed_load"],
                    prescribed_rest=entry["prescribed_rest"],
                    prescribed_notes=entry["prescribed_notes"],
                    log_text=entry["log_text"],
                    parsed_rpe=entry["parsed_rpe"],
                    parsed_notes=entry["parsed_notes"],
                )
                imported_rows += 1
                if entry["parsed_rpe"] is not None:
                    imported_rpe_rows += 1

    return {
        "sessions": imported_sessions,
        "rows": imported_rows,
        "rows_with_rpe": imported_rpe_rows,
    }


def load_config(path):
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def resolve_sheet_list(reader, explicit_sheet, limit):
    if explicit_sheet:
        return [explicit_sheet]

    sheet_names = reader.get_all_weekly_plan_sheets()
    if limit and limit > 0:
        return sheet_names[-limit:]
    return sheet_names


def main():
    args = parse_args()
    config = load_config(args.config)

    google_cfg = config.get("google_sheets", {})
    spreadsheet_id = google_cfg.get("spreadsheet_id")
    credentials_file = google_cfg.get("credentials_file")
    service_account_file = (
        args.service_account_file
        or google_cfg.get("service_account_file")
        or None
    )

    if not spreadsheet_id:
        raise ValueError("Missing google_sheets.spreadsheet_id in config")
    if not credentials_file:
        raise ValueError("Missing google_sheets.credentials_file in config")

    reader = SheetsReader(
        credentials_file=credentials_file,
        spreadsheet_id=spreadsheet_id,
        sheet_name=google_cfg.get("sheet_name", "Sheet1"),
        service_account_file=service_account_file,
    )
    reader.authenticate()

    sheet_names = resolve_sheet_list(reader, args.sheet, args.limit)
    if not sheet_names:
        print("No weekly plan sheets found to import.")
        return

    db = WorkoutDB(args.db_path)
    db.init_schema()

    total_sessions = 0
    total_rows = 0
    total_rpe_rows = 0

    print(f"Importing {len(sheet_names)} sheet(s)...")
    for index, sheet_name in enumerate(sheet_names, start=1):
        stats = import_one_sheet(
            reader=reader,
            db=db,
            spreadsheet_id=spreadsheet_id,
            sheet_name=sheet_name,
            dry_run=args.dry_run,
        )

        total_sessions += stats["sessions"]
        total_rows += stats["rows"]
        total_rpe_rows += stats["rows_with_rpe"]

        print(
            f"[{index}/{len(sheet_names)}] {sheet_name}: "
            f"{stats['sessions']} sessions, {stats['rows']} rows, {stats['rows_with_rpe']} with RPE"
        )

    if args.dry_run:
        print(
            f"\nDry run complete: {total_sessions} sessions, "
            f"{total_rows} exercise rows, {total_rpe_rows} rows with RPE markers."
        )
        db.close()
        return

    summary = db.count_summary()
    db.close()

    print("\nImport complete.")
    print(f"Database: {args.db_path}")
    print(f"- Exercises: {summary['exercises']}")
    print(f"- Sessions: {summary['sessions']}")
    print(f"- Exercise logs: {summary['exercise_logs']}")
    print(f"- Logs with parsed RPE: {summary['logs_with_rpe']}")


if __name__ == "__main__":
    main()
