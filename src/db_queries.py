"""
Shared SQLite query helpers for front-end pages.

All functions take an open sqlite3.Connection and return plain dicts/lists.
"""

import re
import sqlite3


LOAD_RE = re.compile(r"([\d.]+)")


def _parse_load(value):
    """Extract numeric load from a string like '26 kg' or '26.5'."""
    if value is None:
        return None
    match = LOAD_RE.search(str(value).strip())
    return float(match.group(1)) if match else None


def _parse_int(value):
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def get_db_path():
    """Resolve DB path from config with fallback."""
    import os
    import yaml

    try:
        with open("config.yaml", "r", encoding="utf-8") as f:
            config = yaml.safe_load(f) or {}
        return (config.get("database", {}) or {}).get("path") or "data/workout_history.db"
    except (OSError, yaml.YAMLError):
        return "data/workout_history.db"


def get_connection(db_path=None):
    """Return a read-only connection with Row factory."""
    path = db_path or get_db_path()
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    return conn


# ── Exercise Encyclopedia queries ──────────────────────────────────────


def list_all_exercises(conn):
    """Return all canonical exercises with stats."""
    return conn.execute(
        """
        SELECT
            e.id,
            e.name,
            e.normalized_name,
            COUNT(el.id) AS log_count,
            MAX(ws.session_date) AS last_seen,
            MIN(ws.session_date) AS first_seen
        FROM exercises e
        LEFT JOIN exercise_logs el ON el.exercise_id = e.id
        LEFT JOIN workout_sessions ws ON ws.id = el.session_id
        GROUP BY e.id
        ORDER BY e.name COLLATE NOCASE
        """
    ).fetchall()


def get_exercise_aliases(conn, exercise_id):
    """Return alias names for an exercise."""
    row = conn.execute(
        "SELECT normalized_name FROM exercises WHERE id = ?", (exercise_id,)
    ).fetchone()
    if not row:
        return []
    canonical_key = row["normalized_name"]
    return conn.execute(
        "SELECT raw_name FROM exercise_aliases WHERE canonical_key = ? ORDER BY raw_name",
        (canonical_key,),
    ).fetchall()


def get_exercise_history(conn, exercise_id, limit=50):
    """Return full log history for one exercise, newest first."""
    return conn.execute(
        """
        SELECT
            ws.session_date,
            ws.day_label,
            ws.sheet_name,
            el.block,
            el.prescribed_sets,
            el.prescribed_reps,
            el.prescribed_load,
            el.prescribed_rest,
            el.prescribed_notes,
            el.log_text,
            el.parsed_rpe
        FROM exercise_logs el
        JOIN workout_sessions ws ON ws.id = el.session_id
        WHERE el.exercise_id = ?
        ORDER BY
            CASE WHEN ws.session_date IS NULL THEN 1 ELSE 0 END,
            ws.session_date DESC,
            el.id DESC
        LIMIT ?
        """,
        (exercise_id, limit),
    ).fetchall()


def get_exercise_pr(conn, exercise_id):
    """Return the heaviest prescribed load for an exercise."""
    rows = get_exercise_history(conn, exercise_id, limit=200)
    best_load = None
    best_row = None
    for row in rows:
        load = _parse_load(row["prescribed_load"])
        if load is not None and (best_load is None or load > best_load):
            best_load = load
            best_row = row
    if best_row is None:
        return None
    return {
        "load": best_load,
        "reps": best_row["prescribed_reps"],
        "sets": best_row["prescribed_sets"],
        "date": best_row["session_date"],
    }


# ── Session History queries ────────────────────────────────────────────


def list_sessions(conn, limit=60):
    """Return recent sessions with exercise count."""
    return conn.execute(
        """
        SELECT
            ws.id,
            ws.sheet_name,
            ws.day_label,
            ws.day_name,
            ws.session_date,
            COUNT(el.id) AS exercise_count,
            SUM(CASE WHEN el.parsed_rpe IS NOT NULL THEN 1 ELSE 0 END) AS rpe_count,
            SUM(CASE WHEN COALESCE(TRIM(el.log_text), '') <> '' THEN 1 ELSE 0 END) AS logged_count
        FROM workout_sessions ws
        LEFT JOIN exercise_logs el ON el.session_id = ws.id
        GROUP BY ws.id
        ORDER BY
            CASE WHEN ws.session_date IS NULL THEN 1 ELSE 0 END,
            ws.session_date DESC,
            ws.id DESC
        LIMIT ?
        """,
        (limit,),
    ).fetchall()


def get_session_exercises(conn, session_id):
    """Return all exercise logs for a session."""
    return conn.execute(
        """
        SELECT
            e.name AS exercise_name,
            el.block,
            el.prescribed_sets,
            el.prescribed_reps,
            el.prescribed_load,
            el.prescribed_rest,
            el.prescribed_notes,
            el.log_text,
            el.parsed_rpe,
            el.source_row
        FROM exercise_logs el
        JOIN exercises e ON e.id = el.exercise_id
        WHERE el.session_id = ?
        ORDER BY el.source_row
        """,
        (session_id,),
    ).fetchall()


# ── Progression Tracker queries ────────────────────────────────────────


def get_load_progression(conn, exercise_id, limit=30):
    """Return (date, load, reps, rpe) tuples for charting, oldest first."""
    rows = conn.execute(
        """
        SELECT
            ws.session_date,
            el.prescribed_load,
            el.prescribed_reps,
            el.prescribed_sets,
            el.parsed_rpe
        FROM exercise_logs el
        JOIN workout_sessions ws ON ws.id = el.session_id
        WHERE el.exercise_id = ?
          AND ws.session_date IS NOT NULL
        ORDER BY ws.session_date ASC, el.source_row ASC
        LIMIT ?
        """,
        (exercise_id, limit),
    ).fetchall()

    points = []
    for row in rows:
        load = _parse_load(row["prescribed_load"])
        if load is None:
            continue
        reps = _parse_int(row["prescribed_reps"])
        sets = _parse_int(row["prescribed_sets"])
        volume = (sets or 1) * (reps or 1) * load
        points.append(
            {
                "date": row["session_date"],
                "load": load,
                "reps": reps,
                "sets": sets,
                "volume": round(volume, 1),
                "rpe": row["parsed_rpe"],
            }
        )
    return points


def get_top_exercises_by_volume(conn, limit=12):
    """Return exercises ranked by total historical volume."""
    return conn.execute(
        """
        SELECT
            e.id,
            e.name,
            COUNT(el.id) AS log_count,
            MAX(ws.session_date) AS last_seen
        FROM exercise_logs el
        JOIN exercises e ON e.id = el.exercise_id
        JOIN workout_sessions ws ON ws.id = el.session_id
        GROUP BY e.id
        ORDER BY log_count DESC
        LIMIT ?
        """,
        (limit,),
    ).fetchall()
