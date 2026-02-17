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


def build_fort_compiler_context(day_text_map, max_exercises_per_section=4):
    """
    Build deterministic parser directives for Monday/Wednesday/Friday Fort workouts.

    Returns:
      (context_text, metadata_dict)
    """
    parsed_days = []
    ordered_days = ["Monday", "Wednesday", "Friday"]
    for day_name in ordered_days:
        parsed_days.append(parse_fort_day(day_name, day_text_map.get(day_name, "")))

    confidences = [day["confidence"] for day in parsed_days if day["sections"]]
    overall_confidence = round(sum(confidences) / len(confidences), 2) if confidences else 0.0

    lines = [
        "FORT COMPILER DIRECTIVES (PROGRAM-AGNOSTIC):",
        f"Overall parser confidence: {overall_confidence:.2f}",
        "Use detected section order and listed exercise anchors as hard conversion constraints for Fort days.",
    ]

    for parsed in parsed_days:
        day_label = parsed["day"].upper()
        lines.append(f"\n{day_label} (confidence {parsed['confidence']:.2f})")
        if parsed["title_line"]:
            lines.append(f"- Title: {parsed['title_line']}")

        if not parsed["sections"]:
            lines.append("- No reliable sections detected; fall back to raw text for this day.")
            continue

        for section in parsed["sections"]:
            exercises = section["exercises"][:max_exercises_per_section]
            exercise_text = "; ".join(exercises) if exercises else "no anchors extracted"
            lines.append(
                f"- [{section['block_hint']}-block] {section['section_label']} | "
                f"header: {section['raw_header']} | anchors: {exercise_text}"
            )

        for warning in parsed["warnings"]:
            lines.append(f"- Warning: {warning}")

    context_text = "\n".join(lines)
    metadata = {
        "overall_confidence": overall_confidence,
        "days": parsed_days,
    }
    return context_text, metadata
