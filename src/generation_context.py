"""
Build compact SQLite context for AI workout generation.
"""

import os
import sqlite3

from src.workout_db import normalize_exercise_name


def _safe_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _truncate(text, limit=90):
    text = (text or "").strip()
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"


def _add_target(ordered, seen, name, source):
    display_name = (name or "").strip()
    if not display_name:
        return False
    normalized = normalize_exercise_name(display_name)
    if not normalized or normalized in seen:
        return False
    seen.add(normalized)
    ordered.append({"name": display_name, "normalized": normalized, "source": source})
    return True


def _extract_target_exercises(prior_supplemental, max_exercises, fort_compiler_meta=None):
    """Collect unique target exercise names from Fort anchors + prior supplemental days."""
    ordered = []
    seen = set()

    day_specs = (fort_compiler_meta or {}).get("days") or []
    for day_spec in day_specs:
        for section in day_spec.get("compiled_sections", []):
            for exercise in section.get("exercises", []):
                if _add_target(ordered, seen, exercise.get("exercise"), source="fort_anchor"):
                    if len(ordered) >= max_exercises:
                        return ordered

    if not prior_supplemental:
        return ordered

    for day in ["Tuesday", "Thursday", "Saturday"]:
        for ex in prior_supplemental.get(day, []):
            if _add_target(ordered, seen, ex.get("exercise"), source="prior_supplemental"):
                if len(ordered) >= max_exercises:
                    return ordered
    return ordered


def _fetch_recent_focus_exercises(conn, exclude_normalized=None, limit=6):
    """Fallback pool of recent frequently logged exercises with log text."""
    exclude = set(exclude_normalized or set())
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        """
        SELECT
            e.name,
            e.normalized_name,
            COUNT(*) AS log_count,
            MAX(ws.session_date) AS last_date
        FROM exercise_logs el
        JOIN exercises e ON e.id = el.exercise_id
        JOIN workout_sessions ws ON ws.id = el.session_id
        WHERE COALESCE(TRIM(el.log_text), '') <> ''
        GROUP BY e.id
        ORDER BY
            CASE WHEN MAX(ws.session_date) IS NULL THEN 1 ELSE 0 END,
            MAX(ws.session_date) DESC,
            log_count DESC
        LIMIT ?
        """,
        (max(limit * 2, limit),),
    ).fetchall()

    selected = []
    for row in rows:
        normalized = (row["normalized_name"] or "").strip()
        if not normalized or normalized in exclude:
            continue
        selected.append(
            {
                "name": (row["name"] or "").strip(),
                "normalized": normalized,
                "source": "db_recent",
            }
        )
        if len(selected) >= limit:
            return selected
    return selected


def _fetch_recent_logs_for_exercise(conn, normalized_name, logs_per_exercise):
    """Get latest logs for one normalized exercise name."""
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        """
        SELECT
            ws.session_date,
            ws.day_label,
            el.log_text,
            el.parsed_rpe
        FROM exercise_logs el
        JOIN exercises e ON e.id = el.exercise_id
        JOIN workout_sessions ws ON ws.id = el.session_id
        WHERE e.normalized_name = ?
          AND COALESCE(TRIM(el.log_text), '') <> ''
        ORDER BY
            CASE WHEN ws.session_date IS NULL THEN 1 ELSE 0 END,
            ws.session_date DESC,
            el.id DESC
        LIMIT ?
        """,
        (normalized_name, logs_per_exercise),
    ).fetchall()
    return rows


def _fetch_global_summary(conn):
    """Return compact DB totals."""
    conn.row_factory = sqlite3.Row
    row = conn.execute(
        """
        SELECT
            (SELECT COUNT(*) FROM exercises) AS exercises_count,
            (SELECT COUNT(*) FROM workout_sessions) AS sessions_count,
            (SELECT COUNT(*) FROM exercise_logs) AS logs_count,
            (SELECT COUNT(*) FROM exercise_logs WHERE parsed_rpe IS NOT NULL) AS rpe_count
        """
    ).fetchone()
    if not row:
        return None

    logs_count = _safe_int(row["logs_count"])
    rpe_count = _safe_int(row["rpe_count"])
    rpe_pct = (rpe_count / logs_count * 100.0) if logs_count else 0.0
    return {
        "exercises": _safe_int(row["exercises_count"]),
        "sessions": _safe_int(row["sessions_count"]),
        "logs": logs_count,
        "rpe_count": rpe_count,
        "rpe_pct": rpe_pct,
    }


def build_db_generation_context(
    db_path,
    prior_supplemental=None,
    fort_compiler_meta=None,
    max_exercises=10,
    logs_per_exercise=2,
):
    """
    Build token-efficient longitudinal context from SQLite history.

    Returns:
        Compact multiline string or None when unavailable.
    """
    if not db_path or not os.path.exists(db_path):
        return None

    conn = sqlite3.connect(db_path)
    try:
        summary = _fetch_global_summary(conn)
        if not summary:
            return None

        targets = _extract_target_exercises(
            prior_supplemental,
            max_exercises=max_exercises,
            fort_compiler_meta=fort_compiler_meta,
        )
        if len(targets) < max_exercises:
            fallback = _fetch_recent_focus_exercises(
                conn,
                exclude_normalized={target["normalized"] for target in targets},
                limit=max_exercises - len(targets),
            )
            targets.extend(fallback)
        if not targets:
            return None

        lines = [
            "LONGITUDINAL DB CONTEXT (SQLite):",
            (
                f"- Snapshot: {summary['exercises']} exercises | {summary['sessions']} sessions | "
                f"{summary['logs']} logs | RPE coverage {summary['rpe_pct']:.1f}%."
            ),
            "- Target exercise logs (Fort anchors + prior supplemental + recent history):",
        ]

        added = 0
        for target in targets:
            display_name = target["name"]
            normalized_name = target["normalized"]
            recent_logs = _fetch_recent_logs_for_exercise(
                conn,
                normalized_name=normalized_name,
                logs_per_exercise=logs_per_exercise,
            )
            if not recent_logs:
                continue

            compact_entries = []
            for row in recent_logs:
                day_or_date = row["session_date"] or row["day_label"] or "Unknown"
                log_text = _truncate(row["log_text"], limit=85)
                if row["parsed_rpe"] is not None and "rpe" not in (row["log_text"] or "").lower():
                    log_text = f"{log_text} | RPE {row['parsed_rpe']:.1f}"
                compact_entries.append(f"{day_or_date}: {log_text}")

            lines.append(f"  - {display_name} -> " + " || ".join(compact_entries))
            added += 1

        if added == 0:
            return None

        lines.append(
            "- Use this for longer-term trend awareness; selected prior-week sheet remains primary for immediate progression."
        )
        return "\n".join(lines)
    finally:
        conn.close()
