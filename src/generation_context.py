"""
Build compact SQLite context for AI workout generation.
"""

import os
import sqlite3

from src.exercise_normalizer import get_normalizer


def normalize_exercise_name(name):
    """Delegate to ExerciseNormalizer for canonical key."""
    return get_normalizer().canonical_key(name)


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


def _source_label(source):
    labels = {
        "fort_anchor": "FORT",
        "prior_supplemental": "PRIOR",
        "db_recent": "HISTORY",
        "ai_selected": "DB",
    }
    return labels.get(source, "HISTORY")


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


def _fetch_recent_focus_exercises(conn, exclude_normalized=None, limit=8):
    """Fallback pool of recent frequently logged exercises (with or without log text)."""
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
    """Get latest logs for one normalized exercise name, including structured prescription data."""
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        """
        SELECT
            ws.session_date,
            ws.day_label,
            el.prescribed_sets,
            el.prescribed_reps,
            el.prescribed_load,
            el.log_text,
            el.parsed_rpe
        FROM exercise_logs el
        JOIN exercises e ON e.id = el.exercise_id
        JOIN workout_sessions ws ON ws.id = el.session_id
        WHERE e.normalized_name = ?
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
    max_exercises=18,
    logs_per_exercise=4,
    max_chars=3800,
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

        return _build_context_lines(conn, summary, targets, max_chars, logs_per_exercise)
    finally:
        conn.close()


def build_targeted_db_context(db_path, exercise_names, logs_per_exercise=4, max_chars=3200):
    """
    Build DB context for a specific list of exercise names (from two-pass generation).

    This is called after the AI's exercise-selection pass returns the exercises
    it plans to use.  Only those exercises get DB history pulled.

    Args:
        db_path: Path to SQLite database.
        exercise_names: List of exercise name strings from the AI selection pass.
        logs_per_exercise: How many recent logs to pull per exercise.
        max_chars: Token budget for the context block.

    Returns:
        Compact multiline string or None.
    """
    if not db_path or not os.path.exists(db_path) or not exercise_names:
        return None

    normalizer = get_normalizer()
    conn = sqlite3.connect(db_path)
    try:
        summary = _fetch_global_summary(conn)
        if not summary:
            return None

        # Deduplicate and build target list from AI-selected exercise names.
        seen = set()
        targets = []
        for name in exercise_names:
            name = (name or "").strip()
            if not name:
                continue
            norm = normalizer.canonical_key(name)
            if not norm or norm in seen:
                continue
            seen.add(norm)
            targets.append({"name": name, "normalized": norm, "source": "ai_selected"})

        if not targets:
            return None

        return _build_context_lines(conn, summary, targets, max_chars, logs_per_exercise)
    finally:
        conn.close()


def _build_context_lines(conn, summary, targets, max_chars, logs_per_exercise):
    """Shared logic for building compact context lines from target exercises."""
    lines = [
        "EXERCISE HISTORY FROM DATABASE:",
        (
            f"- DB: {summary['exercises']} exercises | {summary['sessions']} sessions | "
            f"{summary['logs']} logs | RPE coverage {summary['rpe_pct']:.1f}%."
        ),
        "- Recent prescription + performance data for selected exercises:",
    ]

    def _fits_within_budget(candidate_lines):
        if not max_chars or max_chars <= 0:
            return True
        return len("\n".join(candidate_lines)) <= max_chars

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
            # Build structured prescription prefix
            rx_parts = []
            if row["prescribed_sets"]:
                rx_parts.append(str(row["prescribed_sets"]).strip())
            if row["prescribed_reps"]:
                rx_parts.append(str(row["prescribed_reps"]).strip())
            if row["prescribed_load"]:
                rx_parts.append(f"@{str(row['prescribed_load']).strip()}")
            rx_str = "x".join(rx_parts[:2])
            if len(rx_parts) >= 3:
                rx_str = f"{rx_str} {rx_parts[2]}"

            log_text = _truncate(row["log_text"] or "", limit=70)
            if row["parsed_rpe"] is not None and "rpe" not in (row["log_text"] or "").lower():
                log_text = f"{log_text} | RPE {row['parsed_rpe']:.1f}" if log_text else f"RPE {row['parsed_rpe']:.1f}"

            entry = f"{day_or_date}: {rx_str}"
            if log_text:
                entry = f"{entry} [{log_text}]"
            compact_entries.append(entry)

        source_tag = _source_label(target.get("source"))
        candidate_line = f"  - [{source_tag}] {display_name} -> " + " || ".join(compact_entries)
        if not _fits_within_budget(lines + [candidate_line]):
            lines.append("- Context truncated to stay within prompt budget.")
            break

        lines.append(candidate_line)
        added += 1

    if added == 0:
        lines.append("- No matching exercise history found in database.")
        return "\n".join(lines)

    tail_line = (
        "- Use this for load/rep reference; prior-week sheet remains primary for immediate progression."
    )
    if _fits_within_budget(lines + [tail_line]):
        lines.append(tail_line)
    return "\n".join(lines)
