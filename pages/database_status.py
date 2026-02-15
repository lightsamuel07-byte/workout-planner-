"""
Database Status page - visibility into local SQLite workout history.
"""

import os
import sqlite3
from datetime import datetime

import streamlit as st
import yaml

from src.ui_utils import action_button, empty_state, render_page_header
from src.sheets_reader import SheetsReader
from src.workout_db import WorkoutDB
from scripts.import_google_sheets_history import import_one_sheet


def get_db_path():
    """Resolve DB path from config with fallback."""
    try:
        with open("config.yaml", "r", encoding="utf-8") as f:
            config = yaml.safe_load(f) or {}
        return (config.get("database", {}) or {}).get("path") or "data/workout_history.db"
    except (OSError, yaml.YAMLError):
        return "data/workout_history.db"


def _fetch_one(conn, query, params=()):
    row = conn.execute(query, params).fetchone()
    return row[0] if row else 0


def _fetch_all(conn, query, params=()):
    conn.row_factory = sqlite3.Row
    return conn.execute(query, params).fetchall()


def bootstrap_database_from_sheets(db_path):
    """
    Build local SQLite database by importing all weekly plan sheets.
    Useful for fresh Streamlit Cloud instances.
    """
    with open("config.yaml", "r", encoding="utf-8") as f:
        config = yaml.safe_load(f) or {}

    google_cfg = config.get("google_sheets", {}) or {}
    spreadsheet_id = google_cfg.get("spreadsheet_id")
    credentials_file = google_cfg.get("credentials_file")
    service_account_file = google_cfg.get("service_account_file") or None

    if not spreadsheet_id:
        raise ValueError("Missing google_sheets.spreadsheet_id in config.yaml")
    if not credentials_file:
        raise ValueError("Missing google_sheets.credentials_file in config.yaml")

    reader = SheetsReader(
        credentials_file=credentials_file,
        spreadsheet_id=spreadsheet_id,
        sheet_name=google_cfg.get("sheet_name", "Sheet1"),
        service_account_file=service_account_file,
    )
    reader.authenticate()
    sheet_names = reader.get_all_weekly_plan_sheets()
    if not sheet_names:
        raise RuntimeError("No weekly plan sheets found to import.")

    db = WorkoutDB(db_path)
    db.init_schema()
    try:
        total_sessions = 0
        total_rows = 0
        total_rpe_rows = 0
        for sheet_name in sheet_names:
            stats = import_one_sheet(
                reader=reader,
                db=db,
                spreadsheet_id=spreadsheet_id,
                sheet_name=sheet_name,
                dry_run=False,
            )
            total_sessions += stats["sessions"]
            total_rows += stats["rows"]
            total_rpe_rows += stats["rows_with_rpe"]

        summary = db.count_summary()
        return {
            "sheet_count": len(sheet_names),
            "imported_sessions": total_sessions,
            "imported_rows": total_rows,
            "imported_rpe_rows": total_rpe_rows,
            "db_summary": summary,
        }
    finally:
        db.close()


def show():
    """Render the database status page."""
    render_page_header("Database Status", "SQLite health and history coverage")

    db_path = get_db_path()

    if not os.path.exists(db_path):
        empty_state(
            "",
            "No Local Database Found",
            "This cloud session has no local SQLite file yet."
        )
        st.info(
            "Your online app runs in a separate environment from your laptop, "
            "so local DB files are not automatically shared."
        )
        st.code(f"python3 scripts/import_google_sheets_history.py --db-path {db_path}")
        if st.button("Build DB from Google Sheets now", type="primary", width="stretch"):
            with st.spinner("Importing weekly plan history from Google Sheets..."):
                try:
                    result = bootstrap_database_from_sheets(db_path)
                    st.success(
                        "DB created successfully from "
                        f"{result['sheet_count']} sheet(s): "
                        f"{result['db_summary']['sessions']} sessions, "
                        f"{result['db_summary']['exercise_logs']} exercise logs."
                    )
                    st.rerun()
                except Exception as exc:
                    st.error(f"Could not build DB automatically: {exc}")
        action_button("Back to Dashboard", "dashboard", width="stretch")
        return

    file_size_kb = os.path.getsize(db_path) / 1024
    modified_dt = datetime.fromtimestamp(os.path.getmtime(db_path))
    st.caption(
        f"DB file: `{db_path}` | {file_size_kb:.1f} KB | Updated {modified_dt.strftime('%Y-%m-%d %I:%M %p')}"
    )

    conn = sqlite3.connect(db_path)
    try:
        total_exercises = _fetch_one(conn, "SELECT COUNT(*) FROM exercises")
        total_sessions = _fetch_one(conn, "SELECT COUNT(*) FROM workout_sessions")
        total_logs = _fetch_one(conn, "SELECT COUNT(*) FROM exercise_logs")
        total_rpe = _fetch_one(conn, "SELECT COUNT(*) FROM exercise_logs WHERE parsed_rpe IS NOT NULL")

        rpe_pct = (total_rpe / total_logs * 100) if total_logs else 0.0

        c1, c2, c3, c4 = st.columns(4)
        c1.metric("Exercises", f"{total_exercises:,}")
        c2.metric("Sessions", f"{total_sessions:,}")
        c3.metric("Exercise Logs", f"{total_logs:,}")
        c4.metric("RPE Coverage", f"{rpe_pct:.1f}%")

        st.markdown("---")
        st.markdown("### Recent Sessions")
        recent_sessions = _fetch_all(
            conn,
            """
            SELECT
                COALESCE(session_date, 'Unknown') AS session_date,
                day_label,
                COUNT(el.id) AS exercise_count,
                SUM(CASE WHEN el.parsed_rpe IS NOT NULL THEN 1 ELSE 0 END) AS rpe_count
            FROM workout_sessions ws
            LEFT JOIN exercise_logs el ON el.session_id = ws.id
            GROUP BY ws.id
            ORDER BY
                CASE WHEN ws.session_date IS NULL THEN 1 ELSE 0 END,
                ws.session_date DESC,
                ws.id DESC
            LIMIT 12
            """
        )
        if recent_sessions:
            st.dataframe(
                [
                    {
                        "Date": row["session_date"],
                        "Session": row["day_label"],
                        "Exercises": row["exercise_count"],
                        "With RPE": row["rpe_count"] or 0,
                    }
                    for row in recent_sessions
                ],
                width="stretch",
                hide_index=True,
            )
        else:
            st.info("No sessions found in database yet.")

        st.markdown("---")
        st.markdown("### Top Logged Exercises")
        top_exercises = _fetch_all(
            conn,
            """
            SELECT
                e.name AS exercise,
                COUNT(el.id) AS logged_times,
                ROUND(AVG(el.parsed_rpe), 2) AS avg_rpe
            FROM exercise_logs el
            JOIN exercises e ON e.id = el.exercise_id
            GROUP BY e.id
            ORDER BY logged_times DESC, exercise ASC
            LIMIT 15
            """
        )

        if top_exercises:
            st.dataframe(
                [
                    {
                        "Exercise": row["exercise"],
                        "Logged Times": row["logged_times"],
                        "Avg RPE": row["avg_rpe"] if row["avg_rpe"] is not None else "-",
                    }
                    for row in top_exercises
                ],
                width="stretch",
                hide_index=True,
            )

        st.markdown("---")
        st.markdown("### RPE Capture Trend (Last 8 Weeks)")
        trend_rows = _fetch_all(
            conn,
            """
            SELECT
                strftime('%Y-%W', session_date) AS week_key,
                COUNT(el.id) AS total_logs,
                SUM(CASE WHEN el.parsed_rpe IS NOT NULL THEN 1 ELSE 0 END) AS rpe_logs
            FROM workout_sessions ws
            JOIN exercise_logs el ON el.session_id = ws.id
            WHERE ws.session_date IS NOT NULL
            GROUP BY week_key
            ORDER BY week_key DESC
            LIMIT 8
            """
        )

        if trend_rows:
            trend_rows = list(reversed(trend_rows))
            coverage_values = [
                (row["rpe_logs"] / row["total_logs"] * 100) if row["total_logs"] else 0
                for row in trend_rows
            ]
            week_labels = [row["week_key"] for row in trend_rows]
            st.line_chart({"RPE %": coverage_values}, height=200)
            st.caption("Weeks: " + " | ".join(week_labels))
            st.caption("Percentage of logged exercises that include an RPE value.")
        else:
            st.info("No dated session rows available for trend chart yet.")
    finally:
        conn.close()
