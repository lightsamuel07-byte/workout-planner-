"""
Program-agnostic Fort workout parsing and deterministic prompt directives.
"""

import re

from src.exercise_normalizer import get_normalizer


SECTION_RULE_DEFS = [
    {
        "section_id": "conditioning",
        "section_label": "Conditioning/THAW",
        "block_hint": "F",
        "patterns": [
            r"\bTHAW\b",
            r"\bREDEMPTION\b",
            r"\bFINISHER\b",
            r"\bCONDITIONING\b",
            r"\bCONDITIONING\s+TEST\b",
            r"\bGARAGE\b.*\b(?:ROW|BIKE|BIKEERG|RUN|SKI|ERG|MILE)\b",
            r"\b(?:\d+\s*K|\d+\s*MILE)\b.*\b(?:ROW|BIKE|BIKEERG|RUN|SKI|ERG)\b.*\bTEST\b",
        ],
    },
    {
        "section_id": "strength_backoff",
        "section_label": "Strength Back-Offs",
        "block_hint": "D",
        "patterns": [
            r"\bBACK[\s\-]*OFFS?\b",
        ],
    },
    {
        "section_id": "strength_build",
        "section_label": "Strength Build-Up/Warm-Up",
        "block_hint": "B",
        "patterns": [
            r"\bCLUSTER\s+WARM\s*UP\b",
            r"\bBUILD\s*UP\b",
            r"\bRAMP\b",
            r"\bCALIBRATION\b",
        ],
    },
    {
        "section_id": "power_activation",
        "section_label": "Power/Activation",
        "block_hint": "B",
        "patterns": [
            r"\bFANNING\s+THE\s+FLAMES\b",
            r"\bPOWER\b",
            r"\bREACTIVITY\b",
        ],
    },
    {
        "section_id": "auxiliary_hypertrophy",
        "section_label": "Auxiliary/Hypertrophy",
        "block_hint": "E",
        "patterns": [
            r"\bAUXILIARY\b",
            r"\bIT\s+BURNS\b",
            r"\bMYO\s*REP\b",
            r"\bACCESSORY\b",
            r"\bUPPER\s+BODY\s+AUX\b",
            r"\bLOWER\s+BODY\s+AUX\b",
        ],
    },
    {
        "section_id": "strength_work",
        "section_label": "Main Strength/Breakpoint",
        "block_hint": "C",
        "patterns": [
            r"\bCLUSTER\s+SET\b",
            r"\bWORKING\s+SET\b",
            r"\bBARBELL\s+BREAKPOINT\b",
            r"\bDUMBBELL\s+BREAKPOINT\b",
            r"\bBODYWEIGHT\s+BREAKPOINT\b",
            r"\bBREAKPOINT\b",
            r"\bCAULDRON\b",
            r"\b(?:1|3)\s*RM\s+TEST\b",
            r"\bMAX\s+PULL[\s\-]*UP\s+TEST\b",
            r"\bMAX\s+PUSH[\s\-]*UP\s+TEST\b",
        ],
    },
    {
        "section_id": "prep_mobility",
        "section_label": "Prep/Mobility",
        "block_hint": "A",
        "patterns": [
            r"\bIGNITION\b",
            r"\bPREP\b",
            r"\bWARM\s*UP\b",
            r"\bTARGETED\s+WARM[\s\-]*UP\b",
            r"\bACTIVATION\b",
            r"\bKOT\s+WARM[\s\-]*UP\b",
        ],
    },
]

SECTION_RULES = [
    {
        **rule,
        "compiled_patterns": [re.compile(pattern, re.IGNORECASE) for pattern in rule["patterns"]],
    }
    for rule in SECTION_RULE_DEFS
]

METADATA_EXACT = {
    "TIPS",
    "TIPS HISTORY",
    "HISTORY",
    "COMPLETE",
    "RX",
    "REPS",
    "WEIGHT",
    "TIME",
    "TIME (MM:SS)",
    "HEIGHT (IN)",
    "DIST. (M)",
    "WATTS",
    "OTHER NUMBER",
    "SETS",
}

METADATA_RE = [
    re.compile(r"^\d+\s*(SETS?|REPS?)$", re.IGNORECASE),
    re.compile(r"^\d+(?:\.\d+)?%$", re.IGNORECASE),
    re.compile(r"^\d+(?:\.\d+)?$", re.IGNORECASE),
    re.compile(r"^\d{1,2}:\d{2}(?:\.\d+)?$", re.IGNORECASE),
    re.compile(r"^(REPS?|WEIGHT|TIME|TIME\s*\(MM:SS\)|HEIGHT\s*\(IN\)|DIST\.?\s*\(M\)|WATTS|OTHER NUMBER|RX)$", re.IGNORECASE),
]

PLAN_DAY_RE = re.compile(r"^\s*##\s+([A-Z]+DAY)\b", re.IGNORECASE)
PLAN_EXERCISE_RE = re.compile(r"^\s*###\s+([A-Z]\d+)\.\s*(.+)$", re.IGNORECASE)
PLAN_PRESCRIPTION_RE = re.compile(
    r"^\s*-\s*(\d+)\s*x\s*([\d:]+)\s*@\s*([\d]+(?:\.\d+)?)\s*kg\b",
    re.IGNORECASE,
)

NON_EXERCISE_PATTERNS = [
    re.compile(r"^TIPS?\b", re.IGNORECASE),
    re.compile(r"^REST\b", re.IGNORECASE),
    re.compile(r"^RIGHT\s+INTO\b", re.IGNORECASE),
    re.compile(r"^START\s+WITH\b", re.IGNORECASE),
    re.compile(r"^THIS\s+IS\b", re.IGNORECASE),
    re.compile(r"^YOU\s+ARE\b", re.IGNORECASE),
    re.compile(r"^OPTIONAL\b", re.IGNORECASE),
    re.compile(r"^REMINDER\b", re.IGNORECASE),
    re.compile(r"^NUMBER\s+OF\s+REPS\b", re.IGNORECASE),
    re.compile(r"^WRITE\s+NOTES\b", re.IGNORECASE),
    re.compile(r"^HIP\s+CIRCLE\s+IS\s+OPTIONAL\b", re.IGNORECASE),
]


def _normalize_space(value):
    return re.sub(r"\s+", " ", (value or "").strip())


def _is_mostly_upper(value):
    chars = [char for char in value if char.isalpha()]
    if len(chars) < 3:
        return False
    upper = sum(1 for char in chars if char.isupper())
    return (upper / len(chars)) >= 0.6


def _is_narrative_line(value):
    words = value.split()
    chars = [char for char in value if char.isalpha()]
    if len(words) <= 6 or len(chars) < 12:
        return False
    lower = sum(1 for char in chars if char.islower())
    return (lower / len(chars)) > 0.35


def _match_section_rule(value):
    normalized = _normalize_space(value)
    if not normalized or not _is_mostly_upper(normalized):
        return None
    words = normalized.split()
    if len(words) > 12:
        return None
    if normalized.endswith(".") and len(words) > 6:
        return None

    for rule in SECTION_RULES:
        for pattern in rule["compiled_patterns"]:
            if pattern.search(normalized):
                return rule
    return None


def find_first_section_index(lines):
    """Return index of the first recognized Fort section header line."""
    if not lines:
        return None

    for idx, line in enumerate(lines[:400]):
        if _match_section_rule(line):
            return idx
    return None


def _is_metadata_line(value):
    normalized = _normalize_space(value)
    if not normalized:
        return True

    upper = normalized.upper()
    if upper in METADATA_EXACT:
        return True

    for pattern in METADATA_RE:
        if pattern.match(normalized):
            return True

    return False


def _is_exercise_candidate(value):
    normalized = _normalize_space(value)
    if not normalized:
        return False
    if _match_section_rule(normalized):
        return False
    if _is_metadata_line(normalized):
        return False
    if any(pattern.search(normalized) for pattern in NON_EXERCISE_PATTERNS):
        return False
    if _is_narrative_line(normalized):
        return False
    if normalized.endswith(":") and len(normalized.split()) <= 6:
        return False
    if len(normalized) > 80:
        return False
    if ":" in normalized and len(normalized.split()) > 4:
        return False
    if not re.search(r"[A-Za-z]", normalized):
        return False
    return True


def _should_seed_section_header_as_exercise(section_id, header_line):
    """
    Some Fort test-week headers include the benchmark modality itself
    (e.g., 'GARAGE - 2K BIKEERG') and should be preserved as anchors.
    """
    if section_id != "conditioning":
        return False
    normalized = _normalize_space(header_line).upper()
    if "TEST" not in normalized and "GARAGE" not in normalized:
        return False
    return bool(re.search(r"\b(ROW|BIKE|BIKEERG|RUN|SKI|ERG|MILE)\b", normalized))


def _extract_day_header(lines):
    nonempty = [_normalize_space(line) for line in lines if _normalize_space(line)]
    if not nonempty:
        return "", ""

    date_line = ""
    title_line = ""

    for line in nonempty[:8]:
        upper = line.upper()
        if not date_line and re.search(r"\b(MONDAY|TUESDAY|WEDNESDAY|THURSDAY|FRIDAY|SATURDAY|SUNDAY)\b", upper) and re.search(r"\d", line):
            date_line = line
            continue
        if not title_line and not _match_section_rule(line) and len(line.split()) <= 12:
            title_line = line

    return date_line, title_line


def parse_fort_day(day_name, workout_text):
    """
    Parse one Fort day into canonical section/exercise anchors.

    Returns a dict with keys:
      day, date_line, title_line, sections, confidence, warnings, total_exercises
    """
    text = (workout_text or "").strip()
    lines = text.splitlines()
    date_line, title_line = _extract_day_header(lines)

    sections = []
    warnings = []
    current_section = None

    for raw_line in lines:
        line = _normalize_space(raw_line)
        if not line:
            continue

        if line.upper().startswith("COMPLETE "):
            maybe_section = _normalize_space(line[9:])
            if _match_section_rule(maybe_section):
                line = maybe_section

        section_rule = _match_section_rule(line)
        if section_rule:
            current_section = {
                "section_id": section_rule["section_id"],
                "section_label": section_rule["section_label"],
                "block_hint": section_rule["block_hint"],
                "raw_header": line,
                "exercises": [],
            }
            if _should_seed_section_header_as_exercise(section_rule["section_id"], line):
                current_section["exercises"].append(line)
            sections.append(current_section)
            continue

        if not current_section:
            continue

        if _is_exercise_candidate(line):
            existing = {
                _normalize_space(exercise).upper()
                for exercise in current_section["exercises"]
            }
            dedupe_key = _normalize_space(line).upper()
            if dedupe_key not in existing:
                current_section["exercises"].append(line)

    section_count = len(sections)
    total_exercises = sum(len(section["exercises"]) for section in sections)
    present_section_ids = {section["section_id"] for section in sections}
    core_ids = {
        "prep_mobility",
        "strength_work",
        "auxiliary_hypertrophy",
        "conditioning",
    }
    coverage = len(present_section_ids.intersection(core_ids)) / len(core_ids)

    section_score = min(1.0, section_count / 6.0)
    exercise_score = min(1.0, total_exercises / 14.0)
    confidence = round((0.45 * section_score) + (0.35 * exercise_score) + (0.20 * coverage), 2)

    if section_count == 0:
        warnings.append("No recognized section headers detected.")
    if total_exercises == 0 and section_count > 0:
        warnings.append("Sections found but no exercise anchors extracted.")

    return {
        "day": day_name,
        "date_line": date_line,
        "title_line": title_line,
        "sections": sections,
        "total_exercises": total_exercises,
        "confidence": confidence,
        "warnings": warnings,
    }


def _normalize_exercise_name(value):
    return re.sub(r"[^a-z0-9]+", " ", (value or "").lower()).strip()


def _extract_day_name(value):
    upper = (value or "").upper()
    for day in ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]:
        if day in upper:
            return day
    return None


def _is_main_lift_name(value):
    normalized = _normalize_exercise_name(value)
    if " db " in f" {normalized} " or "dumbbell" in normalized:
        return False
    return any(token in normalized for token in ["squat", "deadlift", "bench press", "chest press"])


def _section_base_rank(section_id):
    mapping = {
        "prep_mobility": 1,
        "power_activation": 2,
        "strength_build": 2,
        "strength_work": 3,
        "strength_backoff": 4,
        "auxiliary_hypertrophy": 5,
        "conditioning": 6,
    }
    return mapping.get(section_id, 6)


def _rank_to_letter(rank):
    bounded = max(1, min(int(rank), 26))
    return chr(64 + bounded)


def _block_rank(block_label):
    if not block_label:
        return None
    letter = block_label[0].upper()
    if "A" <= letter <= "Z":
        return (ord(letter) - ord("A")) + 1
    return None


def _build_compiled_templates(parsed_day, max_exercises_per_section):
    section_blocks = []
    used_ranks = set()
    current_rank = 1

    for section in parsed_day.get("sections", []):
        desired_rank = _section_base_rank(section["section_id"])
        rank = max(desired_rank, current_rank)
        while rank in used_ranks and rank <= 26:
            rank += 1
        if rank > 26:
            rank = max(used_ranks) + 1 if used_ranks else 1
        rank = min(rank, 26)
        used_ranks.add(rank)
        current_rank = rank
        letter = _rank_to_letter(rank)

        exercises = section["exercises"][:max_exercises_per_section]
        exercise_blocks = []
        for idx, exercise_name in enumerate(exercises, start=1):
            exercise_blocks.append(
                {
                    "block": f"{letter}{idx}",
                    "exercise": exercise_name,
                    "section_id": section["section_id"],
                    "section_label": section["section_label"],
                    "raw_header": section["raw_header"],
                }
            )

        section_blocks.append(
            {
                "section_id": section["section_id"],
                "section_label": section["section_label"],
                "raw_header": section["raw_header"],
                "block_letter": letter,
                "exercises": exercise_blocks,
            }
        )

    return section_blocks


def _build_alias_map(exercise_aliases):
    alias_map = {}
    if not exercise_aliases:
        return alias_map

    for source, target in exercise_aliases.items():
        source_keys = _alias_keys(source)
        target_keys = _alias_keys(target)
        if not source_keys or not target_keys:
            continue
        for source_norm in source_keys:
            for target_norm in target_keys:
                alias_map.setdefault(source_norm, set()).add(target_norm)
                alias_map.setdefault(target_norm, set()).add(source_norm)

    return alias_map


def _canonical_alias_name(value):
    normalized = _normalize_exercise_name(value)
    if not normalized:
        return ""

    # Remove equipment tokens that should not block swap matching.
    normalized = re.sub(r"\b(dumbbell|db)\b", " ", normalized)
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return normalized


def _alias_keys(value):
    normalized = _normalize_exercise_name(value)
    if not normalized:
        return set()

    keys = {normalized}
    canonical = _canonical_alias_name(normalized)
    if canonical:
        keys.add(canonical)

    return {key for key in keys if key}


def _matches_expected_exercise(expected_name, actual_name, alias_map):
    normalizer = get_normalizer()

    # Primary: use the canonical normalizer
    if normalizer.are_same_exercise(expected_name, actual_name):
        return True

    # Fallback: legacy alias map for any swap entries not yet in normalizer
    expected_keys = _alias_keys(expected_name)
    actual_keys = _alias_keys(actual_name)
    if not expected_keys or not actual_keys:
        return False

    candidates = set(expected_keys)
    for expected_key in expected_keys:
        candidates.update(alias_map.get(expected_key, set()))
        for alias_source, alias_targets in alias_map.items():
            if alias_source and alias_source in expected_key:
                candidates.update(alias_targets)

    for candidate in candidates:
        for actual_key in actual_keys:
            if candidate == actual_key or candidate in actual_key or actual_key in candidate:
                return True
    return False


def parse_plan_fort_entries(plan_text):
    """Parse generated markdown plan entries by day for Fort fidelity checks."""
    entries_by_day = {}
    current_day = None
    current_entry = None

    for line in (plan_text or "").splitlines():
        day_match = PLAN_DAY_RE.match(line)
        if day_match:
            current_day = _extract_day_name(day_match.group(1))
            current_entry = None
            if current_day:
                entries_by_day.setdefault(current_day, [])
            continue

        exercise_match = PLAN_EXERCISE_RE.match(line)
        if exercise_match and current_day:
            block = exercise_match.group(1).strip()
            exercise = exercise_match.group(2).strip()
            current_entry = {
                "day": current_day,
                "block": block,
                "block_rank": _block_rank(block),
                "exercise": exercise,
                "load": None,
                "reps": None,
                "notes": "",
            }
            entries_by_day.setdefault(current_day, []).append(current_entry)
            continue

        if not current_entry:
            continue

        prescription_match = PLAN_PRESCRIPTION_RE.match(line.strip())
        if prescription_match:
            _sets, reps, load = prescription_match.groups()
            current_entry["reps"] = reps
            current_entry["load"] = float(load)
            continue

        notes_line = line.strip()
        if notes_line.lower().startswith("- **notes:**"):
            current_entry["notes"] = notes_line

    return entries_by_day


def _weekday_rank(day_name):
    order = {
        "MONDAY": 1,
        "TUESDAY": 2,
        "WEDNESDAY": 3,
        "THURSDAY": 4,
        "FRIDAY": 5,
        "SATURDAY": 6,
        "SUNDAY": 7,
    }
    return order.get((day_name or "").upper(), 99)


def _parse_plan_day_segments(plan_text):
    lines = (plan_text or "").splitlines()
    prefix_lines = []
    segments = []
    current = None

    for line in lines:
        day_match = PLAN_DAY_RE.match(line)
        day_name = _extract_day_name(day_match.group(1)) if day_match else None
        if day_name:
            if current:
                segments.append(current)
            current = {"day": day_name, "lines": [line]}
            continue

        if current:
            current["lines"].append(line)
        else:
            prefix_lines.append(line)

    if current:
        segments.append(current)

    return prefix_lines, segments


def _parse_day_entries_with_spans(day_lines):
    entries = []
    for idx, line in enumerate(day_lines):
        exercise_match = PLAN_EXERCISE_RE.match(line)
        if not exercise_match:
            continue

        block = exercise_match.group(1).strip()
        block_match = re.match(r"^([A-Z])(\d+)$", block, re.IGNORECASE)
        block_letter = block_match.group(1).upper() if block_match else ""
        block_index = int(block_match.group(2)) if block_match else 0

        entries.append(
            {
                "start_idx": idx,
                "end_idx": len(day_lines),
                "block": block,
                "block_letter": block_letter,
                "block_index": block_index,
                "block_rank": _block_rank(block),
                "exercise": exercise_match.group(2).strip(),
            }
        )

    for idx, entry in enumerate(entries):
        next_start = entries[idx + 1]["start_idx"] if idx + 1 < len(entries) else len(day_lines)
        entry["end_idx"] = next_start

    return entries


def _default_block_lines(block_label, exercise_name, section_id):
    sets, reps, load, rest = _repair_default_prescription(section_id, exercise_name)
    return [
        f"### {block_label}. {exercise_name}",
        f"- {sets} x {reps} @ {load} kg",
        f"- **Rest:** {rest}",
        "- **Notes:** Added by deterministic Fort anchor repair. Replace prescription with exact Fort values if needed.",
    ]


def _normalize_block_lines(block_label, exercise_name, source_lines, section_id):
    default_lines = _default_block_lines(block_label, exercise_name, section_id)
    if not source_lines:
        return default_lines, True

    prescription_line = None
    rest_line = None
    notes_line = None

    for raw in source_lines[1:]:
        line = (raw or "").strip()
        if not line:
            continue
        if prescription_line is None and PLAN_PRESCRIPTION_RE.match(line):
            prescription_line = line
            continue
        if rest_line is None and line.lower().startswith("- **rest:**"):
            rest_line = line
            continue
        if notes_line is None and line.lower().startswith("- **notes:**"):
            notes_line = line

    missing = False
    if prescription_line is None:
        prescription_line = default_lines[1]
        missing = True
    if rest_line is None:
        rest_line = default_lines[2]
        missing = True
    if notes_line is None:
        notes_line = default_lines[3]
        missing = True

    normalized_lines = [
        f"### {block_label}. {exercise_name}",
        prescription_line,
        rest_line,
        notes_line,
    ]
    return normalized_lines, missing


def _repair_default_prescription(section_id, exercise_name):
    is_main = _is_main_lift_name(exercise_name)
    exercise_norm = _normalize_exercise_name(exercise_name)
    is_db = " db " in f" {exercise_norm} " or "dumbbell" in exercise_norm

    if section_id in {"prep_mobility", "conditioning"}:
        return "1", "60", "0", "None"
    if is_main:
        return "1", "1", "20", "180 seconds"
    if is_db:
        return "3", "10", "10", "90 seconds"
    return "3", "10", "0", "90 seconds"


def _join_plan_segments(prefix_lines, segments):
    lines = list(prefix_lines)
    for segment in segments:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend(segment["lines"])
    return "\n".join(lines).rstrip() + "\n"


def repair_plan_fort_anchors(plan_text, fort_metadata, exercise_aliases=None):
    """
    Deterministically insert missing Fort anchors into generated markdown plans.

    Returns:
      (patched_plan_text, repair_summary_dict)
    """
    if not plan_text:
        return plan_text, {"inserted": 0, "insertions": [], "summary": "Fort anchor repair skipped: empty plan."}

    day_specs = (fort_metadata or {}).get("days") or []
    if not day_specs:
        return plan_text, {"inserted": 0, "insertions": [], "summary": "Fort anchor repair skipped: no metadata."}

    alias_map = _build_alias_map(exercise_aliases or {})
    prefix_lines, segments = _parse_plan_day_segments(plan_text)
    segments_by_day = {segment["day"]: segment for segment in segments}

    inserted = []
    dropped_entries = 0
    rebuilt_days = 0
    added_day = False

    for day_spec in day_specs:
        day_name = (day_spec.get("day") or "").upper()
        compiled_sections = day_spec.get("compiled_sections") or []
        if not day_name or not compiled_sections:
            continue

        segment = segments_by_day.get(day_name)
        if not segment:
            segment = {"day": day_name, "lines": [f"## {day_name}"]}
            segments.append(segment)
            segments_by_day[day_name] = segment
            added_day = True

        day_lines = segment["lines"]
        entries = _parse_day_entries_with_spans(day_lines)
        block_entries = []
        for entry in entries:
            block_entries.append(
                {
                    **entry,
                    "lines": day_lines[entry["start_idx"]:entry["end_idx"]],
                    "used": False,
                }
            )

        header_line = segment["lines"][0] if segment["lines"] and PLAN_DAY_RE.match(segment["lines"][0]) else f"## {day_name}"
        rebuilt_lines = [header_line]

        for section in compiled_sections:
            for expected_entry in section.get("exercises", []):
                expected_name = expected_entry.get("exercise") or ""
                expected_block = expected_entry.get("block") or f"{section.get('block_letter', 'Z')}1"
                if not expected_name:
                    continue

                match = None
                for entry in block_entries:
                    if entry["used"]:
                        continue
                    if _matches_expected_exercise(expected_name, entry["exercise"], alias_map):
                        match = entry
                        break

                if match:
                    match["used"] = True
                    normalized_lines, missing_fields = _normalize_block_lines(
                        expected_block,
                        expected_name,
                        match.get("lines"),
                        section["section_id"],
                    )
                    if missing_fields:
                        inserted.append(
                            {
                                "day": day_name,
                                "section_id": section["section_id"],
                                "exercise": expected_name,
                                "block": expected_block,
                            }
                        )
                else:
                    normalized_lines = _default_block_lines(expected_block, expected_name, section["section_id"])
                    inserted.append(
                        {
                            "day": day_name,
                            "section_id": section["section_id"],
                            "exercise": expected_name,
                            "block": expected_block,
                        }
                    )

                if len(rebuilt_lines) > 1:
                    rebuilt_lines.append("")
                rebuilt_lines.extend(normalized_lines)

        dropped_entries += sum(1 for entry in block_entries if not entry["used"])
        segment["lines"] = rebuilt_lines
        rebuilt_days += 1

    if rebuilt_days == 0:
        return plan_text, {"inserted": 0, "insertions": [], "dropped": 0, "summary": "Fort anchor repair skipped: no Fort days rebuilt."}

    if added_day:
        segments.sort(key=lambda segment: _weekday_rank(segment.get("day")))
    patched = _join_plan_segments(prefix_lines, segments)

    summary = (
        f"Fort anchor repair: rebuilt {rebuilt_days} Fort day(s), inserted {len(inserted)} missing/filled anchor(s), "
        f"dropped {dropped_entries} non-anchor entry block(s)."
    )
    return patched, {
        "inserted": len(inserted),
        "insertions": inserted,
        "dropped": dropped_entries,
        "rebuilt_days": rebuilt_days,
        "summary": summary,
    }


def validate_fort_fidelity(plan_text, fort_metadata, exercise_aliases=None):
    """
    Validate Fort day conversion fidelity against parsed compiler metadata.

    Returns:
      dict with keys: violations, summary, expected_anchors, matched_anchors
    """
    if not fort_metadata:
        return {
            "violations": [],
            "summary": "Fort fidelity: no compiler metadata provided.",
            "expected_anchors": 0,
            "matched_anchors": 0,
        }

    day_specs = fort_metadata.get("days", [])
    if not day_specs:
        return {
            "violations": [],
            "summary": "Fort fidelity: no parsed Fort days to validate.",
            "expected_anchors": 0,
            "matched_anchors": 0,
        }

    alias_map = _build_alias_map(exercise_aliases or {})
    entries_by_day = parse_plan_fort_entries(plan_text)

    violations = []
    expected_anchors = 0
    matched_anchors = 0

    for day_spec in day_specs:
        day_name = (day_spec.get("day") or "").upper()
        compiled_sections = day_spec.get("compiled_sections") or []
        if not compiled_sections:
            continue

        actual_entries = entries_by_day.get(day_name, [])
        if not actual_entries:
            violations.append(
                {
                    "code": "fort_day_missing",
                    "message": f"{day_name} is missing from generated plan.",
                    "day": day_name,
                    "exercise": "",
                }
            )
            expected_anchors += sum(len(section.get("exercises", [])) for section in compiled_sections)
            continue

        day_used_indices = set()
        section_ranks = []

        for section in compiled_sections:
            section_matches = []
            for expected_entry in section.get("exercises", []):
                expected_anchors += 1
                matched_index = None
                for idx, actual_entry in enumerate(actual_entries):
                    if idx in day_used_indices:
                        continue
                    if _matches_expected_exercise(
                        expected_entry["exercise"],
                        actual_entry["exercise"],
                        alias_map,
                    ):
                        matched_index = idx
                        break

                if matched_index is None:
                    violations.append(
                        {
                            "code": "fort_missing_anchor",
                            "message": (
                                f"Missing Fort anchor exercise '{expected_entry['exercise']}' "
                                f"from section '{section['section_label']}' on {day_name}."
                            ),
                            "day": day_name,
                            "exercise": expected_entry["exercise"],
                        }
                    )
                    continue

                day_used_indices.add(matched_index)
                matched_entry = actual_entries[matched_index]
                matched_anchors += 1
                section_matches.append(matched_entry)

                if section["section_id"] in {"strength_build", "strength_work", "strength_backoff"}:
                    if _is_main_lift_name(expected_entry["exercise"]):
                        if matched_entry.get("load") is None or matched_entry.get("load", 0) <= 0:
                            violations.append(
                                {
                                    "code": "fort_missing_load",
                                    "message": (
                                        f"Expected explicit load for main Fort lift "
                                        f"'{matched_entry['exercise']}' on {day_name}."
                                    ),
                                    "day": day_name,
                                    "exercise": matched_entry["exercise"],
                                }
                            )

                notes_text = (matched_entry.get("notes") or "").lower()
                if "added by deterministic fort anchor repair" in notes_text:
                    violations.append(
                        {
                            "code": "fort_placeholder_prescription",
                            "message": (
                                f"Fort anchor '{matched_entry['exercise']}' on {day_name} "
                                "still has deterministic placeholder notes."
                            ),
                            "day": day_name,
                            "exercise": matched_entry["exercise"],
                        }
                    )

            ranks = [entry["block_rank"] for entry in section_matches if entry.get("block_rank") is not None]
            if ranks:
                section_ranks.append(
                    {
                        "section_id": section["section_id"],
                        "section_label": section["section_label"],
                        "rank": min(ranks),
                    }
                )

        previous = None
        for section_rank in section_ranks:
            if previous and section_rank["rank"] < previous["rank"]:
                violations.append(
                    {
                        "code": "fort_section_order",
                        "message": (
                            f"Fort section order drift on {day_name}: "
                            f"'{section_rank['section_label']}' appears before "
                            f"'{previous['section_label']}'."
                        ),
                        "day": day_name,
                        "exercise": "",
                    }
                )
            previous = section_rank

    summary = (
        f"Fort fidelity: {matched_anchors}/{expected_anchors} anchors matched, "
        f"{len(violations)} violation(s)."
        if expected_anchors
        else "Fort fidelity: no anchors available to validate."
    )

    return {
        "violations": violations,
        "summary": summary,
        "expected_anchors": expected_anchors,
        "matched_anchors": matched_anchors,
    }


def _render_day_template(parsed_day):
    lines = []
    title_suffix = f" ({parsed_day['title_line']})" if parsed_day.get("title_line") else ""
    lines.append(f"## {parsed_day['day'].upper()}{title_suffix}")

    for section in parsed_day.get("compiled_sections", []):
        for exercise in section.get("exercises", []):
            lines.append(f"### {exercise['block']}. {exercise['exercise']}")
            lines.append(
                f"- Section: {section['section_label']} | Header: {section['raw_header']} | "
                f"Prescription: preserve from Fort source."
            )
        lines.append("")

    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)


def build_fort_compiler_context(day_text_map, max_exercises_per_section=4):
    """
    Build deterministic parser directives for Monday/Wednesday/Friday Fort workouts.

    Returns:
      (context_text, metadata_dict)
    """
    parsed_days = []
    ordered_days = ["Monday", "Wednesday", "Friday"]
    for day_name in ordered_days:
        parsed = parse_fort_day(day_name, day_text_map.get(day_name, ""))
        parsed["compiled_sections"] = _build_compiled_templates(parsed, max_exercises_per_section)
        parsed["compiled_template"] = _render_day_template(parsed)
        parsed_days.append(parsed)

    confidences = [day["confidence"] for day in parsed_days if day["sections"]]
    overall_confidence = round(sum(confidences) / len(confidences), 2) if confidences else 0.0

    lines = [
        "FORT COMPILER DIRECTIVES (PROGRAM-AGNOSTIC):",
        f"Overall parser confidence: {overall_confidence:.2f}",
        "Use detected section order and listed exercise anchors as hard conversion constraints for Fort days.",
        "Use the normalized template blocks below as deterministic shape constraints.",
    ]

    for parsed in parsed_days:
        day_label = parsed["day"].upper()
        lines.append(f"\n{day_label} (confidence {parsed['confidence']:.2f})")
        if parsed["title_line"]:
            lines.append(f"- Title: {parsed['title_line']}")

        if not parsed["sections"]:
            lines.append("- No reliable sections detected; fall back to raw text for this day.")
            continue

        for section in parsed["compiled_sections"]:
            exercise_names = [entry["exercise"] for entry in section.get("exercises", [])]
            exercise_text = "; ".join(exercise_names) if exercise_names else "no anchors extracted"
            lines.append(
                f"- [{section['block_letter']}-block] {section['section_label']} | "
                f"header: {section['raw_header']} | anchors: {exercise_text}"
            )

        lines.append("- Normalized template:")
        lines.append(parsed["compiled_template"])

        for warning in parsed["warnings"]:
            lines.append(f"- Warning: {warning}")

    context_text = "\n".join(lines)
    metadata = {
        "overall_confidence": overall_confidence,
        "days": parsed_days,
    }
    return context_text, metadata
