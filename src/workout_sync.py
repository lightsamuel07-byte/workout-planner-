"""
Helpers to sync workout logs into local SQLite history.
"""

import re
from datetime import date, datetime, timedelta

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
RPE_PATTERN = re.compile(r"\brpe\s*[:=]?\s*(\d+(?:\.\d+)?)\b", re.IGNORECASE)


def extract_day_name(text):
    """Extract day name from labels like 'Tuesday 1/20'."""
    if not text:
        return None
    match = DAY_PATTERN.search(text)
    if not match:
        return None
    return match.group(1).capitalize()


def parse_sheet_anchor_date(sheet_name):
    """Parse anchor date from weekly sheet name."""
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
    """Choose year nearest to anchor date for day labels without year."""
    if not anchor_date:
        return datetime.now().year

    candidates = []
    for year in [anchor_date.year - 1, anchor_date.year, anchor_date.year + 1]:
        try:
            candidates.append(date(year, month, day))
        except ValueError:
            continue

    if not candidates:
        return anchor_date.year

    nearest = min(candidates, key=lambda d: abs((d - anchor_date).days))
    return nearest.year


def infer_date_from_anchor(anchor_date, day_name):
    """Infer session date by matching weekday in anchor week."""
    if not anchor_date or not day_name:
        return None

    target_weekday = DAY_NAME_TO_INDEX.get(day_name.lower())
    if target_weekday is None:
        return None

    for offset in range(0, 7):
        candidate = anchor_date + timedelta(days=offset)
        if candidate.weekday() == target_weekday:
            return candidate

    for offset in range(1, 8):
        candidate = anchor_date - timedelta(days=offset)
        if candidate.weekday() == target_weekday:
            return candidate

    return None


def infer_session_date(sheet_name, day_label, day_name, fallback_date_iso=None):
    """Infer ISO date from sheet name/day label, with safe fallback."""
    anchor_date = parse_sheet_anchor_date(sheet_name)
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
            year = best_year_for_month_day(anchor_date, month, day)

        try:
            return date(year, month, day).isoformat()
        except ValueError:
            pass

    inferred = infer_date_from_anchor(anchor_date, day_name)
    if inferred:
        return inferred.isoformat()

    return fallback_date_iso


def coerce_rpe(explicit_rpe, log_text):
    """
    Return float RPE from explicit field, then fallback parse from log text.
    """
    if explicit_rpe not in (None, ""):
        try:
            value = float(explicit_rpe)
            if 1.0 <= value <= 10.0:
                return value
        except ValueError:
            pass

    match = RPE_PATTERN.search(log_text or "")
    if not match:
        return None

    value = float(match.group(1))
    if 1.0 <= value <= 10.0:
        return value
    return None


def sync_workout_logs_to_db(
    db_path,
    sheet_name,
    day_label,
    fallback_day_name,
    fallback_date_iso,
    entries,
):
    """
    Upsert a workout session and non-empty logged entries into SQLite.

    Args:
        db_path: SQLite file path.
        sheet_name: Google sheet tab name.
        day_label: Session day label from sheet (e.g. "Tuesday 1/20").
        fallback_day_name: Runtime day name if label parsing fails.
        fallback_date_iso: Runtime date as ISO string.
        entries: Iterable of dict entries with keys:
            source_row, exercise_name, block, prescribed_*, log_text, explicit_rpe, parsed_notes
    """
    day_name = extract_day_name(day_label) or fallback_day_name
    session_date = infer_session_date(
        sheet_name=sheet_name,
        day_label=day_label,
        day_name=day_name,
        fallback_date_iso=fallback_date_iso,
    )

    db = WorkoutDB(db_path)
    db.init_schema()

    inserted_logs = 0
    try:
        with db.transaction():
            session_id = db.upsert_session(
                sheet_name=sheet_name,
                day_label=day_label,
                day_name=day_name,
                session_date=session_date,
            )

            for entry in entries:
                exercise_name = (entry.get("exercise_name") or "").strip()
                log_text = (entry.get("log_text") or "").strip()
                if not exercise_name or not log_text:
                    continue

                exercise_id = db.upsert_exercise(exercise_name)
                parsed_rpe = coerce_rpe(entry.get("explicit_rpe"), log_text)
                db.upsert_exercise_log(
                    session_id=session_id,
                    exercise_id=exercise_id,
                    source_row=int(entry.get("source_row", inserted_logs + 1)),
                    block=entry.get("block", ""),
                    prescribed_sets=entry.get("prescribed_sets", ""),
                    prescribed_reps=entry.get("prescribed_reps", ""),
                    prescribed_load=entry.get("prescribed_load", ""),
                    prescribed_rest=entry.get("prescribed_rest", ""),
                    prescribed_notes=entry.get("prescribed_notes", ""),
                    log_text=log_text,
                    parsed_rpe=parsed_rpe,
                    parsed_notes=(entry.get("parsed_notes") or "").strip() or None,
                )
                inserted_logs += 1

        return db.count_summary()
    finally:
        db.close()
