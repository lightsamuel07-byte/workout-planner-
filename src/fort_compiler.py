"""
Program-agnostic Fort workout parsing and deterministic prompt directives.
"""

import re


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
    if _is_narrative_line(normalized):
        return False
    if len(normalized) > 80:
        return False
    if ":" in normalized and len(normalized.split()) > 4:
        return False
    if not re.search(r"[A-Za-z]", normalized):
        return False
    return True


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

        section_rule = _match_section_rule(line)
        if section_rule:
            current_section = {
                "section_id": section_rule["section_id"],
                "section_label": section_rule["section_label"],
                "block_hint": section_rule["block_hint"],
                "raw_header": line,
                "exercises": [],
            }
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
        source_norm = _normalize_exercise_name(source)
        target_norm = _normalize_exercise_name(target)
        if not source_norm or not target_norm:
            continue
        alias_map.setdefault(source_norm, set()).add(target_norm)
        alias_map.setdefault(target_norm, set()).add(source_norm)

    return alias_map


def _matches_expected_exercise(expected_name, actual_name, alias_map):
    expected_norm = _normalize_exercise_name(expected_name)
    actual_norm = _normalize_exercise_name(actual_name)
    if not expected_norm or not actual_norm:
        return False

    candidates = {expected_norm}
    candidates.update(alias_map.get(expected_norm, set()))
    for candidate in candidates:
        if candidate == actual_norm or candidate in actual_norm or actual_norm in candidate:
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

    return entries_by_day


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
