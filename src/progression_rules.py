"""
Deterministic progression directives derived from prior-week logs.
"""

import re

from src.workout_db import normalize_exercise_name
from src.exercise_normalizer import get_normalizer


RPE_VALUE_RE = re.compile(r"\brpe\s*[:=]?\s*(\d+(?:\.\d+)?)\b", re.IGNORECASE)

HOLD_LOCK_PATTERNS = [
    re.compile(pattern, re.IGNORECASE)
    for pattern in [
        r"\bkeep\b",
        r"\bstay here\b",
        r"\bhold\b",
        r"\bsame weight\b",
        r"\bdon't increase\b",
        r"\bdo not increase\b",
        r"\bcan't increase\b",
    ]
]

STRUGGLE_PATTERNS = [
    re.compile(pattern, re.IGNORECASE)
    for pattern in [
        r"\bhard\b",
        r"\bheavy\b",
        r"\btough\b",
        r"\bstruggl",
        r"\bchalleng",
        r"\bfailed\b",
        r"\bform (?:broke|breakdown|wasn't perfect)\b",
    ]
]

EXCEEDED_PATTERNS = [
    re.compile(pattern, re.IGNORECASE)
    for pattern in [
        r"\beasy\b",
        r"\btoo light\b",
        r"\bcould do more\b",
        r"\breps? left\b",
        r"\bgo up\b",
        r"\bincrease\b",
    ]
]


def _parse_float(value):
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return None


def _parse_int(value):
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def _parse_rpe(text):
    match = RPE_VALUE_RE.search(text or "")
    if not match:
        return None

    value = float(match.group(1))
    if 1.0 <= value <= 10.0:
        return value
    return None


def _matches_any(patterns, text):
    for pattern in patterns:
        if pattern.search(text or ""):
            return True
    return False


def _classify_signal(log_text, rpe_value):
    text = log_text or ""

    if _matches_any(HOLD_LOCK_PATTERNS, text):
        return "hold_lock", "explicit_keep_instruction"

    if _matches_any(STRUGGLE_PATTERNS, text):
        return "hold_lock", "struggle_signal"

    if rpe_value is not None and rpe_value >= 9.0:
        return "hold_lock", "high_rpe"

    if _matches_any(EXCEEDED_PATTERNS, text):
        return "progress", "exceeded_signal"

    if rpe_value is not None and rpe_value <= 7.0:
        return "progress", "low_rpe"

    return "neutral", "no_strong_signal"


def _normalize_day_name(day_name):
    return (day_name or "").strip().lower()


def _safe_str(value):
    return str(value).strip() if value is not None else ""


def build_progression_directives(prior_supplemental):
    """
    Build deterministic directives from prior-week supplemental logs.

    Returns:
        List[dict] with keys:
            day_name, exercise_name, normalized_exercise,
            signal, reason, hold_lock, target_reps, target_load,
            parsed_rpe, source_log
    """
    directives = []
    if not prior_supplemental:
        return directives

    for day_name in ["Tuesday", "Thursday", "Saturday"]:
        for exercise in prior_supplemental.get(day_name, []):
            exercise_name = _safe_str(exercise.get("exercise"))
            if not exercise_name:
                continue

            log_text = _safe_str(exercise.get("log"))
            if not log_text:
                continue

            parsed_rpe = _parse_rpe(log_text)
            signal, reason = _classify_signal(log_text, parsed_rpe)
            target_reps = _parse_int(exercise.get("reps"))
            target_load = _parse_float(exercise.get("load"))
            hold_lock = signal == "hold_lock"

            directives.append(
                {
                    "day_name": _normalize_day_name(day_name),
                    "exercise_name": exercise_name,
                    "normalized_exercise": normalize_exercise_name(exercise_name),
                    "signal": signal,
                    "reason": reason,
                    "hold_lock": hold_lock,
                    "target_reps": target_reps,
                    "target_load": target_load,
                    "parsed_rpe": parsed_rpe,
                    "source_log": log_text,
                }
            )

    return directives


def format_directives_for_prompt(directives, max_lines=18):
    """Render compact directive block for prompt context."""
    if not directives:
        return ""

    lines = ["PROGRESSION DIRECTIVES (DETERMINISTIC FROM PRIOR LOGS):"]
    hold_lines = []
    progress_lines = []

    for directive in directives:
        name = directive["exercise_name"]
        day = directive["day_name"].capitalize()
        log_preview = directive["source_log"][:90]

        if directive["hold_lock"]:
            reps = directive["target_reps"]
            load = directive["target_load"]
            hold_lines.append(
                f"- LOCK {day} | {name} -> keep {reps} reps @ {format_load(load)} kg | log: {log_preview}"
            )
        elif directive["signal"] == "progress":
            progress_lines.append(
                f"- PROGRESS {day} | {name} -> progression allowed (single-variable change) | log: {log_preview}"
            )

    selected = hold_lines + progress_lines
    lines.extend(selected[:max_lines])
    return "\n".join(lines)


def format_load(value):
    """Format load values while preserving meaningful decimal precision."""
    if value is None:
        return ""

    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))

    # Keep up to 3 decimals to support cable/machine increments.
    return f"{value:.3f}".rstrip("0").rstrip(".")


def _normalize_for_match(name):
    return get_normalizer().canonical_key(name)


def _find_best_directive(day_name, exercise_name, directive_map):
    normalizer = get_normalizer()
    target_day = _normalize_day_name(day_name)

    # Exact canonical key match
    key = (target_day, normalizer.canonical_key(exercise_name))
    if key in directive_map:
        return directive_map[key]

    # Fuzzy match via normalizer
    for (day_key, exercise_key), directive in directive_map.items():
        if day_key != target_day:
            continue
        if normalizer.are_same_exercise(exercise_name, directive.get("exercise_name", "")):
            return directive
    return None


def apply_locked_directives_to_plan(plan_text, directives):
    """
    Apply deterministic hold-lock directives to generated plan text.

    Returns:
        Tuple[str, int] => (updated_plan_text, num_applied)
    """
    if not plan_text or not directives:
        return plan_text, 0

    locked_directives = [d for d in directives if d.get("hold_lock")]
    if not locked_directives:
        return plan_text, 0

    normalizer = get_normalizer()
    directive_map = {}
    for directive in locked_directives:
        key = (
            _normalize_day_name(directive.get("day_name")),
            normalizer.canonical_key(directive.get("exercise_name")),
        )
        directive_map[key] = directive

    day_re = re.compile(r"^\s*##\s+([A-Z]+DAY)\b", re.IGNORECASE)
    exercise_re = re.compile(r"^\s*###\s+[A-Z]\d+\.\s*(.+)$", re.IGNORECASE)
    prescription_re = re.compile(
        r"^(\s*-\s*)(\d+)\s*x\s*([\d:]+)\s*@\s*([\d]+(?:\.\d+)?)\s*kg(\b.*)$",
        re.IGNORECASE,
    )

    current_day = None
    current_exercise = None
    current_directive = None
    applied = 0
    lines = plan_text.split("\n")

    for idx, line in enumerate(lines):
        day_match = day_re.match(line)
        if day_match:
            current_day = day_match.group(1).capitalize()
            current_exercise = None
            current_directive = None
            continue

        exercise_match = exercise_re.match(line)
        if exercise_match:
            current_exercise = exercise_match.group(1).strip()
            current_directive = _find_best_directive(current_day, current_exercise, directive_map)
            continue

        if not current_directive:
            continue

        prescription_match = prescription_re.match(line)
        if not prescription_match:
            continue

        prefix, sets, reps, _load, suffix = prescription_match.groups()
        target_reps = current_directive.get("target_reps")
        target_load = current_directive.get("target_load")
        if target_reps is None or target_load is None:
            continue

        new_line = f"{prefix}{sets} x {target_reps} @ {format_load(target_load)} kg{suffix}"
        if new_line != line:
            lines[idx] = new_line
            applied += 1

        # Only apply once per exercise prescription line.
        current_directive = None

    return "\n".join(lines), applied
