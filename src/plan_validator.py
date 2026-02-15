"""
Validation utilities for generated workout plans.
"""

import re


DAY_RE = re.compile(r"^\s*##\s+([A-Z]+DAY)\b", re.IGNORECASE)
EXERCISE_RE = re.compile(r"^\s*###\s+[A-Z]\d+\.\s*(.+)$", re.IGNORECASE)
PRESCRIPTION_RE = re.compile(
    r"^\s*-\s*(\d+)\s*x\s*([\d:]+)\s*@\s*([\d]+(?:\.\d+)?)\s*kg\b",
    re.IGNORECASE,
)
RANGE_RE = re.compile(r"(\d+)\s*[-–]\s*(\d+)")


def _normalize_text(value):
    return re.sub(r"[^a-z0-9]+", " ", (value or "").lower()).strip()


def _extract_day_name(value):
    upper = (value or "").upper()
    for day in ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]:
        if day in upper:
            return day
    return None


def _parse_plan_entries(plan_text):
    """Parse markdown plan into structured entries."""
    entries = []
    current_day = None
    current_exercise = None
    current_entry = None

    for line in (plan_text or "").split("\n"):
        day_match = DAY_RE.match(line)
        if day_match:
            current_day = _extract_day_name(day_match.group(1))
            current_exercise = None
            current_entry = None
            continue

        exercise_match = EXERCISE_RE.match(line)
        if exercise_match:
            current_exercise = exercise_match.group(1).strip()
            current_entry = {
                "day": current_day,
                "exercise": current_exercise,
                "normalized_exercise": _normalize_text(current_exercise),
                "prescription_line": "",
                "sets": None,
                "reps": None,
                "load": None,
                "rest": "",
                "notes": "",
            }
            entries.append(current_entry)
            continue

        if not current_entry:
            continue

        stripped = line.strip()
        if stripped.startswith("- **Rest:**"):
            current_entry["rest"] = stripped
            continue
        if stripped.startswith("- **Notes:**"):
            current_entry["notes"] = stripped
            continue

        prescription_match = PRESCRIPTION_RE.match(stripped)
        if prescription_match:
            sets, reps, load = prescription_match.groups()
            current_entry["prescription_line"] = stripped
            current_entry["sets"] = int(sets)
            current_entry["reps"] = reps
            current_entry["load"] = float(load)

    return entries


def _is_main_plate_lift(name):
    value = _normalize_text(name)
    if _is_db_exercise(name):
        return False
    return any(
        token in value
        for token in ["back squat", "front squat", "deadlift", "bench press", "chest press"]
    )


def _is_db_exercise(name):
    value = _normalize_text(name)
    return " db " in f" {value} " or "dumbbell" in value


def _identify_triceps_attachment(name):
    value = _normalize_text(name)
    if "single arm" in value and "d handle" in value:
        return "single_arm_d_handle"
    if "d handle" in value:
        return "d_handle"
    if "rope" in value:
        return "rope"
    if "ez bar" in value:
        return "ez_bar"
    if "straight bar" in value:
        return "straight_bar"
    if "v bar" in value:
        return "v_bar"
    if "bar" in value:
        return "bar"
    return "other"


def _identify_biceps_grip(entry):
    value = _normalize_text(entry.get("exercise"))
    notes = _normalize_text(entry.get("notes"))

    # Prefer explicit "<grip> grip" declarations first.
    for text in [value, notes]:
        match = re.search(r"\b(supinated|pronated|neutral)\s+grip\b", text)
        if match:
            return match.group(1)

    # Exercise name cues are next most reliable.
    if any(token in value for token in ["pronated", "pronation", "reverse curl"]):
        return "pronated"
    if any(token in value for token in ["neutral", "hammer"]):
        return "neutral"
    if any(token in value for token in ["supinated", "supination"]):
        return "supinated"

    # Notes fallback: only use when a single grip signal is present.
    note_signals = set()
    if any(token in notes for token in ["pronated", "pronation", "reverse curl"]):
        note_signals.add("pronated")
    if any(token in notes for token in ["neutral", "hammer"]):
        note_signals.add("neutral")
    if any(token in notes for token in ["supinated", "supination"]):
        note_signals.add("supinated")

    if len(note_signals) == 1:
        return next(iter(note_signals))
    return ""


def _add_violation(violations, code, message, day=None, exercise=None):
    violations.append(
        {
            "code": code,
            "message": message,
            "day": day or "",
            "exercise": exercise or "",
        }
    )


def validate_plan(plan_text, progression_directives=None):
    """
    Validate generated plan for hard-rule adherence.

    Returns:
        dict with keys: entries, violations, summary
    """
    entries = _parse_plan_entries(plan_text)
    violations = []

    for entry in entries:
        exercise = entry["exercise"]
        day = entry["day"]
        prescription = entry["prescription_line"]

        if prescription and RANGE_RE.search(prescription):
            _add_violation(
                violations,
                "range_in_prescription",
                f"Range found in prescription line: {prescription}",
                day=day,
                exercise=exercise,
            )

        if _is_db_exercise(exercise) and not _is_main_plate_lift(exercise) and entry["load"] is not None:
            rounded = int(round(entry["load"]))
            if abs(entry["load"] - rounded) < 1e-9 and rounded % 2 != 0:
                _add_violation(
                    violations,
                    "odd_db_load",
                    f"Odd dumbbell load detected: {entry['load']} kg",
                    day=day,
                    exercise=exercise,
                )

        if "split squat" in _normalize_text(exercise):
            _add_violation(
                violations,
                "forbidden_split_squat",
                "Split squat detected but it is forbidden.",
                day=day,
                exercise=exercise,
            )

        if "carry" in _normalize_text(exercise) and day != "TUESDAY":
            _add_violation(
                violations,
                "carry_wrong_day",
                "Carry exercise appears outside Tuesday.",
                day=day,
                exercise=exercise,
            )

    # Triceps attachment variation across Tue/Fri/Sat.
    triceps_entries = [
        entry
        for entry in entries
        if any(day in (entry["day"] or "") for day in ["TUESDAY", "FRIDAY", "SATURDAY"])
        and "tricep" in _normalize_text(entry["exercise"])
    ]
    if triceps_entries:
        attachments = []
        for entry in triceps_entries:
            attachment = _identify_triceps_attachment(entry["exercise"])
            attachments.append((entry["day"], entry["exercise"], attachment))
            if entry["day"] == "SATURDAY" and attachment == "single_arm_d_handle":
                _add_violation(
                    violations,
                    "single_arm_d_handle_saturday",
                    "Single-arm D-handle triceps work is not allowed on Saturday.",
                    day=entry["day"],
                    exercise=entry["exercise"],
                )

        unique_attachments = {attachment for _, _, attachment in attachments}
        if len(unique_attachments) < 2:
            _add_violation(
                violations,
                "triceps_attachment_rotation",
                "Triceps attachments are not varied across Tue/Fri/Sat.",
            )

    # Biceps grip rotation across Tue/Thu/Sat (no repeated adjacent day grip).
    grip_by_day = {}
    day_order = ["TUESDAY", "THURSDAY", "SATURDAY"]
    for day in day_order:
        day_entries = [
            entry
            for entry in entries
            if entry["day"] == day and "curl" in _normalize_text(entry["exercise"])
        ]
        if not day_entries:
            continue
        grip = ""
        for day_entry in day_entries:
            grip = _identify_biceps_grip(day_entry)
            if grip:
                break
        if grip:
            grip_by_day[day] = grip

    previous_day = None
    previous_grip = None
    for day in day_order:
        grip = grip_by_day.get(day)
        if not grip:
            continue
        if previous_grip and grip == previous_grip:
            _add_violation(
                violations,
                "biceps_grip_repeat",
                f"Biceps grip repeats on consecutive supplemental days ({previous_day} -> {day}): {grip}.",
            )
        previous_day = day
        previous_grip = grip

    # Enforce hold-lock directives.
    for directive in progression_directives or []:
        if not directive.get("hold_lock"):
            continue
        target_day = _extract_day_name(directive.get("day_name"))
        target_ex = _normalize_text(directive.get("exercise_name"))
        target_load = directive.get("target_load")
        target_reps = directive.get("target_reps")
        if target_day is None or target_load is None or target_reps is None:
            continue

        match = None
        for entry in entries:
            if entry["day"] != target_day:
                continue
            normalized = entry["normalized_exercise"]
            if target_ex == normalized or target_ex in normalized or normalized in target_ex:
                match = entry
                break

        if not match:
            continue

        load_mismatch = match["load"] is None or abs(match["load"] - float(target_load)) > 1e-9
        reps_mismatch = str(match["reps"] or "").strip() != str(target_reps)
        if load_mismatch or reps_mismatch:
            _add_violation(
                violations,
                "hold_lock_violation",
                (
                    f"Hold-lock not respected for {directive['exercise_name']}: expected "
                    f"{target_reps} reps @ {target_load} kg."
                ),
                day=match["day"],
                exercise=match["exercise"],
            )

    summary = (
        f"Validation: {len(entries)} exercises checked, {len(violations)} violation(s)."
        if entries
        else "Validation: no exercises parsed from plan."
    )

    return {
        "entries": entries,
        "violations": violations,
        "summary": summary,
    }
