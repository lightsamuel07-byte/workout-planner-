"""
SQLite persistence for normalized workout history.
"""

import os
import re
import sqlite3
from contextlib import contextmanager


def normalize_exercise_name(name):
    """Return a stable normalized key for exercise deduplication."""
    cleaned = re.sub(r'\s+', ' ', (name or '').strip().lower())
    return cleaned


class WorkoutDB:
    """Small SQLite wrapper for workout history storage."""

    def __init__(self, db_path):
        self.db_path = db_path
        parent = os.path.dirname(db_path)
        if parent:
            os.makedirs(parent, exist_ok=True)

        self.conn = sqlite3.connect(db_path)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA foreign_keys = ON")

    def close(self):
        self.conn.close()

    @contextmanager
    def transaction(self):
        """Context manager for atomic write operations."""
        try:
            yield
            self.conn.commit()
        except Exception:
            self.conn.rollback()
            raise

    def init_schema(self):
        """Create core schema if it does not already exist."""
        self.conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS exercises (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                normalized_name TEXT NOT NULL UNIQUE,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS workout_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sheet_name TEXT NOT NULL,
                day_label TEXT NOT NULL,
                day_name TEXT,
                session_date TEXT,
                source TEXT NOT NULL DEFAULT 'google_sheets',
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                UNIQUE(sheet_name, day_label)
            );

            CREATE TABLE IF NOT EXISTS exercise_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL,
                exercise_id INTEGER NOT NULL,
                block TEXT,
                prescribed_sets TEXT,
                prescribed_reps TEXT,
                prescribed_load TEXT,
                prescribed_rest TEXT,
                prescribed_notes TEXT,
                log_text TEXT,
                parsed_rpe REAL,
                parsed_notes TEXT,
                source_row INTEGER NOT NULL,
                source TEXT NOT NULL DEFAULT 'google_sheets',
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                FOREIGN KEY(session_id) REFERENCES workout_sessions(id) ON DELETE CASCADE,
                FOREIGN KEY(exercise_id) REFERENCES exercises(id) ON DELETE RESTRICT,
                UNIQUE(session_id, source_row)
            );

            CREATE INDEX IF NOT EXISTS idx_exercise_logs_session_id ON exercise_logs(session_id);
            CREATE INDEX IF NOT EXISTS idx_exercise_logs_exercise_id ON exercise_logs(exercise_id);
            CREATE INDEX IF NOT EXISTS idx_workout_sessions_date ON workout_sessions(session_date);
            """
        )
        self.conn.commit()

    def upsert_exercise(self, exercise_name):
        """Insert or update an exercise and return its id."""
        normalized = normalize_exercise_name(exercise_name)
        if not normalized:
            raise ValueError("Exercise name cannot be empty")

        self.conn.execute(
            """
            INSERT INTO exercises (name, normalized_name, updated_at)
            VALUES (?, ?, datetime('now'))
            ON CONFLICT(normalized_name) DO UPDATE SET
                name = excluded.name,
                updated_at = datetime('now')
            """,
            (exercise_name.strip(), normalized),
        )

        row = self.conn.execute(
            "SELECT id FROM exercises WHERE normalized_name = ?",
            (normalized,),
        ).fetchone()
        return int(row["id"])

    def upsert_session(self, sheet_name, day_label, day_name, session_date):
        """Insert or update a session and return its id."""
        self.conn.execute(
            """
            INSERT INTO workout_sessions (
                sheet_name,
                day_label,
                day_name,
                session_date,
                source,
                updated_at
            )
            VALUES (?, ?, ?, ?, 'google_sheets', datetime('now'))
            ON CONFLICT(sheet_name, day_label) DO UPDATE SET
                day_name = excluded.day_name,
                session_date = excluded.session_date,
                updated_at = datetime('now')
            """,
            (sheet_name, day_label, day_name, session_date),
        )

        row = self.conn.execute(
            """
            SELECT id
            FROM workout_sessions
            WHERE sheet_name = ? AND day_label = ?
            """,
            (sheet_name, day_label),
        ).fetchone()
        return int(row["id"])

    def upsert_exercise_log(
        self,
        session_id,
        exercise_id,
        source_row,
        block,
        prescribed_sets,
        prescribed_reps,
        prescribed_load,
        prescribed_rest,
        prescribed_notes,
        log_text,
        parsed_rpe,
        parsed_notes,
    ):
        """Insert or update one exercise log row."""
        self.conn.execute(
            """
            INSERT INTO exercise_logs (
                session_id,
                exercise_id,
                block,
                prescribed_sets,
                prescribed_reps,
                prescribed_load,
                prescribed_rest,
                prescribed_notes,
                log_text,
                parsed_rpe,
                parsed_notes,
                source_row,
                source,
                updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'google_sheets', datetime('now'))
            ON CONFLICT(session_id, source_row) DO UPDATE SET
                exercise_id = excluded.exercise_id,
                block = excluded.block,
                prescribed_sets = excluded.prescribed_sets,
                prescribed_reps = excluded.prescribed_reps,
                prescribed_load = excluded.prescribed_load,
                prescribed_rest = excluded.prescribed_rest,
                prescribed_notes = excluded.prescribed_notes,
                log_text = excluded.log_text,
                parsed_rpe = excluded.parsed_rpe,
                parsed_notes = excluded.parsed_notes,
                updated_at = datetime('now')
            """,
            (
                session_id,
                exercise_id,
                block,
                prescribed_sets,
                prescribed_reps,
                prescribed_load,
                prescribed_rest,
                prescribed_notes,
                log_text,
                parsed_rpe,
                parsed_notes,
                source_row,
            ),
        )

    def count_summary(self):
        """Return high-level row counts for quick sanity checks."""
        exercises_count = self.conn.execute("SELECT COUNT(*) AS c FROM exercises").fetchone()["c"]
        sessions_count = self.conn.execute("SELECT COUNT(*) AS c FROM workout_sessions").fetchone()["c"]
        logs_count = self.conn.execute("SELECT COUNT(*) AS c FROM exercise_logs").fetchone()["c"]
        with_rpe_count = self.conn.execute(
            "SELECT COUNT(*) AS c FROM exercise_logs WHERE parsed_rpe IS NOT NULL"
        ).fetchone()["c"]
        return {
            "exercises": int(exercises_count),
            "sessions": int(sessions_count),
            "exercise_logs": int(logs_count),
            "logs_with_rpe": int(with_rpe_count),
        }
