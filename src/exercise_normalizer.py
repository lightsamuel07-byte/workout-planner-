"""
Canonical exercise normalization engine.

Single source of truth for exercise identity across the entire codebase.
All modules use this instead of ad-hoc string matching.
"""

import os
import re
import yaml


# ---------------------------------------------------------------------------
# Parenthetical qualifiers to STRIP (these don't change exercise identity)
# ---------------------------------------------------------------------------
STRIP_PAREN_PATTERNS = [
    re.compile(r"\s*\(warm-?up(?:\s+set)?\s*\d*\)", re.IGNORECASE),
    re.compile(r"\s*\(cluster\s+(?:singles|doubles)\)", re.IGNORECASE),
    re.compile(r"\s*\(build\)", re.IGNORECASE),
    re.compile(r"\s*\(working\)", re.IGNORECASE),
    re.compile(r"\s*\(back-?off\)", re.IGNORECASE),
    re.compile(r"\s*\(emom\)", re.IGNORECASE),
    re.compile(r"\s*\(max\)", re.IGNORECASE),
    re.compile(r"\s*\(last\s+set\s*=\s*myo-?rep\)", re.IGNORECASE),
    re.compile(r"\s*\(myo-?rep\s+finisher\)", re.IGNORECASE),
    re.compile(r"\s*\(std\)", re.IGNORECASE),
    re.compile(r"\s*\(standard\)", re.IGNORECASE),
    re.compile(r"\s*\(no\s+belt\)", re.IGNORECASE),
    re.compile(r"\s*\(finisher\)", re.IGNORECASE),
    re.compile(r"\s*\(flush\)", re.IGNORECASE),
    re.compile(r"\s*\(treadmill\)", re.IGNORECASE),
    re.compile(r"\s*\(opt\)", re.IGNORECASE),
    re.compile(r"\s*\(second\s+set\)", re.IGNORECASE),
    re.compile(r"\s*\(db\s+optional\)", re.IGNORECASE),
    re.compile(r"\s*\(all-?out\)", re.IGNORECASE),
    re.compile(r"\s*\(at\s+pace\)", re.IGNORECASE),
    re.compile(r"\s*\(hold\s+target\)", re.IGNORECASE),
    re.compile(r"\s*\(max\s+power\)", re.IGNORECASE),
    re.compile(r"\s*\(rhythm\s+test\)", re.IGNORECASE),
    re.compile(r"\s*\(sequence\)", re.IGNORECASE),
]

# Post-dash qualifiers to strip: " — BREAKPOINT", " — calibration", " — work", " — calib"
STRIP_DASH_SUFFIX = re.compile(
    r"\s*[—–-]+\s*(?:breakpoint|calibration|calib|work)\s*$", re.IGNORECASE
)

# ---------------------------------------------------------------------------
# Abbreviation normalization (canonical forms)
# ---------------------------------------------------------------------------
ABBREVIATION_MAP = [
    # EZ-bar variants -> EZ-Bar
    (re.compile(r"\bez[\s-]*bar\b", re.IGNORECASE), "EZ-Bar"),
    # BikeErg variants
    (re.compile(r"\bbike\s*erg\b", re.IGNORECASE), "BikeErg"),
    # SkiErg variants
    (re.compile(r"\bski\s*erg\b", re.IGNORECASE), "SkiErg"),
    # RowErg variants
    (re.compile(r"\brow\s*erg\b", re.IGNORECASE), "RowErg"),
]

# ---------------------------------------------------------------------------
# Pluralization normalization (strip trailing 's' for specific words)
# ---------------------------------------------------------------------------
DEPLURALIZE_PATTERNS = [
    (re.compile(r"\bwindmills\b", re.IGNORECASE), "Windmill"),
    (re.compile(r"\bburpees\b", re.IGNORECASE), "Burpee"),
    (re.compile(r"\bplanks\b", re.IGNORECASE), "Plank"),
    (re.compile(r"\bpull-ups\b", re.IGNORECASE), "Pull-Up"),
    (re.compile(r"\bpush-ups\b", re.IGNORECASE), "Push-Up"),
    (re.compile(r"\bface pulls\b", re.IGNORECASE), "Face Pull"),
]

# ---------------------------------------------------------------------------
# Explicit alias groups: names that should resolve to the same canonical form.
# First entry in each group is the canonical display name.
# ---------------------------------------------------------------------------
ALIAS_GROUPS = [
    # Goblet squat variants
    ["Goblet Squat", "Goblet Squat (Std)", "Goblet Squat (standard)"],
    # DB RDL variants
    ["DB RDL (Glute Optimized)", "DB RDL (glute-opt.)"],
    # Heel-elevated goblet squat
    ["Heel-Elevated DB Goblet Squat", "Heels-Elevated DB Goblet Squat"],
    # Side-lying windmill
    ["Side-Lying Windmill", "Side-Lying Windmills"],
    # Poliquin step-up
    ["Poliquin Step-Up", "Poliquin step up", "Poliquin Step-Up (DB optional)"],
    # Face pull family (rope-based)
    ["Face Pull (Rope)", "Face Pull (rope)", "Face Pull (Rope, High-to-Forehead)",
     "Cable Face Pull (rope)", "Cable Face Pull (Rear Delt Emphasis)", "Face Pulls", "Face Pull"],
    # Standing calf raise
    ["Standing Calf Raise", "Standing Calf Raise (Machine)",
     "Standing Calf Raise (Smith Machine or DB)", "Standing/Seated Calf Raise"],
    # Bench / Bench Press unification
    ["Bench Press", "Bench"],
    # McGill Big-3
    ["McGill Big-3", "McGill Big 3 (sequence)", "McGill Big-3 micro"],
    # Incline Walk
    ["Incline Walk", "Incline Walk (Finisher)", "Incline Walk (Warm-up)",
     "Incline Walk (flush)", "Incline Walk (treadmill)"],
    # DB Hammer Curl
    ["DB Hammer Curl", "DB Hammer Curl (neutral)", "Hammer Curl (Neutral Grip)"],
    # Straight-Arm Pulldown
    ["Straight-Arm Cable Pulldown", "Straight-Arm Pulldown"],
    # Low-Hold DB Goblet Squat = Heel-Elevated DB Goblet Squat (different! keep separate)
    # Rope Pressdown family
    ["Rope Pressdown", "Tricep Pushdown (Rope Attachment)"],
    # Overhead rope tricep extension
    ["Overhead Cable Tricep Extension (Rope)", "Overhead Rope Tricep Extension"],
    # Reverse Pec Deck
    ["Reverse Pec Deck", "Reverse Pec Deck (rear-delt)"],
    # Rear-delt cable variants
    ["Rear-Delt Cable/Machine", "Rear-Delt Machine/Cable"],
    # Cable curl pronated
    ["Cable Curl (Straight Bar, Pronated Grip)",
     "Cable Curl (Straight Bar, Overhand/Pronated)"],
    # Seated DB shoulder press variants
    ["Seated DB Shoulder Press", "Seated DB Press"],
    # Chest-supported DB row
    ["Chest-Supported DB Row", "Chest-Supported DB Row (30°)",
     "Chest-Supported Row (30)", "Chest-Supported DB Row (max)"],
    # Kneeling cable crunch
    ["Kneeling Cable Crunch", "Cable Crunch"],
    # Dry Sauna
    ["Dry Sauna", "Dry Sauna (opt)"],
    # Hamstring walkout
    ["Hamstring Bridge Walkouts", "Hamstring Walkout"],
    # DB Sumo Squat
    ["DB Sumo Squat", "DB Sumo Squat (LAST SET = MYO-REP)",
     "DB Sumo Squat (MYO-REP FINISHER)"],
    # Standing EZ Bar Bicep Curl
    ["Standing EZ-Bar Curl", "Standing EZ Bar Bicep Curl (LAST SET = MYO-REP)",
     "Standing EZ Bar Bicep Curl (MYO-REP FINISHER)"],
    # EZ Bar Rear Delt Row
    ["EZ Bar Rear Delt Row", "EZ Bar Rear Delt Row (MYO-REP FINISHER)"],
    # Seated Leg Curl
    ["Seated Leg Curl (machine)", "Seated Leg Curl (roller swap)"],
    # Barbell Curl
    ["Barbell Curl", "Barbell Curl (max)", "Standing Barbell Curl (supinated)"],
    # EZ-Bar Curl
    ["EZ-Bar Curl", "EZ-Bar Curl (max)", "EZ-Bar Curl (reverse grip)"],
    # Pull-Up
    ["Pull-Up", "Pull-Ups", "Pull-Ups (max)"],
    # Push-Up
    ["Push-Up", "Push-Ups", "Push-Ups (max)"],
    # Plyo Push-Up
    ["Plyo Push-Up", "Plyo Push-Up (EMOM)"],
    # BikeErg
    ["BikeErg", "BikeErg (all-out)", "BikeErg (at pace)",
     "BikeErg (hold target)", "BikeErg (max power)"],
    # SkiErg
    ["SkiErg", "SkiErg (at pace)", "SkiErg (hold target)"],
    # Rower
    ["Rower", "Rower (all-out)", "Rower (hold target)", "RowErg Sprints"],
    # 90/90 Hip Switch
    ["90/90 Hip Switch", "90/90 Hip Switch (Second Set)"],
    # Adductor Rockback
    ["Adductor Rockback", "Adductor Rockback (Second Set)"],
    # Ab Rollout
    ["Ab Rollout", "Ab Rollout (wheel/cable bar)"],
    # 15° EZ-Bar Triceps Extension
    ["15° EZ-Bar Triceps Extension", "15° EZ Bar Tricep Extension",
     "15° EZ-Bar Triceps Ext (max)", "15° ez Triceps Extension"],
    # Straight-Bar Triceps Extension
    ["Straight-Bar Triceps Extension (15°)", "Straight-Bar Triceps Ext (max)"],
]

# ---------------------------------------------------------------------------
# Body-part category tokens for fuzzy match safety
# ---------------------------------------------------------------------------
BODY_PART_CATEGORIES = {
    "curl": "biceps",
    "bicep": "biceps",
    "press": "push",
    "bench": "push",
    "fly": "push",
    "squat": "legs_quad",
    "leg extension": "legs_quad",
    "deadlift": "legs_pull",
    "rdl": "legs_pull",
    "row": "back",
    "pulldown": "back",
    "pull-up": "back",
    "lateral raise": "delts",
    "shoulder": "delts",
    "calf": "calves",
    "tricep": "triceps",
    "pushdown": "triceps",
    "skullcrusher": "triceps",
}


class ExerciseNormalizer:
    """
    Canonical exercise normalization and matching.

    Usage:
        normalizer = ExerciseNormalizer()
        normalizer.canonical_key("Back Squat (Warm-up Set 3)")  # -> "back squat"
        normalizer.are_same_exercise("DB RDL (Glute Optimized)", "DB RDL (glute-opt.)")  # -> True
        normalizer.canonical_name("Poliquin step up")  # -> "Poliquin Step-Up"
    """

    def __init__(self, swaps_file="exercise_swaps.yaml"):
        # Build alias lookup: lowered stripped name -> canonical display name
        self._alias_to_canonical = {}
        self._canonical_key_to_display = {}

        # Register alias groups
        for group in ALIAS_GROUPS:
            canonical_display = group[0]
            canonical_key = self._compute_canonical_key(canonical_display)
            self._canonical_key_to_display[canonical_key] = canonical_display
            for alias in group:
                alias_key = self._compute_canonical_key(alias)
                self._alias_to_canonical[alias_key] = canonical_key
                # Also register the raw lowered form for direct lookup
                raw_lower = re.sub(r"\s+", " ", alias.strip().lower())
                self._alias_to_canonical[raw_lower] = canonical_key

        # Load exercise swaps from config
        self._load_swap_aliases(swaps_file)

    def _load_swap_aliases(self, swaps_file):
        """Register exercise_swaps.yaml entries as aliases."""
        if not swaps_file or not os.path.exists(swaps_file):
            return
        try:
            with open(swaps_file, "r") as f:
                config = yaml.safe_load(f) or {}
        except (OSError, yaml.YAMLError):
            return

        for original, replacement in (config.get("exercise_swaps") or {}).items():
            if not original or not replacement:
                continue
            orig_key = self._compute_canonical_key(str(original))
            repl_key = self._compute_canonical_key(str(replacement))
            # The replacement is the canonical form
            if repl_key not in self._canonical_key_to_display:
                self._canonical_key_to_display[repl_key] = str(replacement).strip()
            self._alias_to_canonical[orig_key] = repl_key

    def _compute_canonical_key(self, name):
        """
        Compute the canonical key for deduplication/matching.

        Strips non-identity qualifiers, unifies abbreviations, lowercases.
        """
        if not name:
            return ""

        result = re.sub(r"\s+", " ", name.strip())

        # Strip parenthetical qualifiers that don't change identity
        for pattern in STRIP_PAREN_PATTERNS:
            result = pattern.sub("", result)

        # Strip post-dash suffixes (— BREAKPOINT, — calibration, etc.)
        result = STRIP_DASH_SUFFIX.sub("", result)

        # Unify abbreviations
        for pattern, replacement in ABBREVIATION_MAP:
            result = pattern.sub(replacement, result)

        # Depluralize specific words
        for pattern, replacement in DEPLURALIZE_PATTERNS:
            result = pattern.sub(replacement, result)

        # Collapse whitespace and lowercase
        result = re.sub(r"\s+", " ", result).strip().lower()

        # Normalize common abbreviation spacing: "glute-opt." -> "glute optimized"
        result = result.replace("glute-opt.", "glute optimized")

        return result

    def canonical_key(self, name):
        """
        Return the canonical key for an exercise name.

        This is the stable string used for DB deduplication and matching.
        Resolves through alias registry if a known alias exists.
        """
        if not name:
            return ""
        key = self._compute_canonical_key(name)
        # Direct alias lookup
        if key in self._alias_to_canonical:
            return self._alias_to_canonical[key]

        # Try base-name alias with qualifier recomposition.
        # e.g., "bench (paused)" -> base "bench" has alias "bench press"
        #        -> recompose as "bench press (paused)"
        base, qualifier = self._split_base_qualifier(key)
        if qualifier and base in self._alias_to_canonical:
            canonical_base = self._alias_to_canonical[base]
            return f"{canonical_base} {qualifier}"

        return key

    @staticmethod
    def _split_base_qualifier(key):
        """
        Split a canonical key into base name and trailing qualifier.

        Returns (base, qualifier) where qualifier includes parentheses,
        or (key, "") if no qualifier found.
        """
        match = re.match(r"^(.+?)\s*(\([^)]+\).*)$", key)
        if match:
            return match.group(1).strip(), match.group(2).strip()
        return key, ""

    def canonical_name(self, raw):
        """
        Return the preferred display name for an exercise.

        Falls back to the raw name (title-cased, cleaned) if no alias is registered.
        """
        if not raw:
            return ""
        key = self.canonical_key(raw)
        display = self._canonical_key_to_display.get(key)
        if display:
            return display
        # Fallback: return the input with stripped qualifiers, preserving case
        cleaned = re.sub(r"\s+", " ", raw.strip())
        for pattern in STRIP_PAREN_PATTERNS:
            cleaned = pattern.sub("", cleaned)
        cleaned = STRIP_DASH_SUFFIX.sub("", cleaned)
        return cleaned.strip()

    def are_same_exercise(self, a, b):
        """
        Determine if two exercise names refer to the same exercise.

        Uses canonical key comparison first, then fuzzy matching.
        """
        if not a or not b:
            return False

        key_a = self.canonical_key(a)
        key_b = self.canonical_key(b)

        # Exact canonical match
        if key_a == key_b:
            return True

        # Substring containment (one canonical key contains the other)
        if self._substring_match(key_a, key_b):
            return True

        # Fuzzy token overlap
        return self._fuzzy_match(key_a, key_b)

    def find_match(self, raw, candidates):
        """
        Find the best matching exercise name from a list of candidates.

        Args:
            raw: The exercise name to match
            candidates: List of exercise name strings to search

        Returns:
            The best matching candidate string, or None if no match found.
        """
        if not raw or not candidates:
            return None

        key = self.canonical_key(raw)

        # Pass 1: exact canonical key match
        for candidate in candidates:
            if self.canonical_key(candidate) == key:
                return candidate

        # Pass 2: are_same_exercise (includes fuzzy)
        for candidate in candidates:
            if self.are_same_exercise(raw, candidate):
                return candidate

        return None

    def register_alias(self, raw_name, canonical_display):
        """
        Register a new alias at runtime.

        Args:
            raw_name: The variant name to register
            canonical_display: The canonical display form
        """
        canonical_key = self._compute_canonical_key(canonical_display)
        raw_key = self._compute_canonical_key(raw_name)
        self._alias_to_canonical[raw_key] = canonical_key
        if canonical_key not in self._canonical_key_to_display:
            self._canonical_key_to_display[canonical_key] = canonical_display

    def is_db_exercise(self, name):
        """Check if exercise uses dumbbells."""
        key = self._compute_canonical_key(name)
        return " db " in f" {key} " or "dumbbell" in key

    def is_main_plate_lift(self, name):
        """Check if exercise is a main barbell lift."""
        key = self._compute_canonical_key(name)
        if self.is_db_exercise(name):
            return False
        return any(
            token in key
            for token in ["back squat", "front squat", "deadlift", "bench press", "chest press"]
        )

    # -------------------------------------------------------------------
    # Internal matching helpers
    # -------------------------------------------------------------------

    def _tokenize(self, key):
        """Split canonical key into meaningful tokens."""
        return set(re.split(r"[^a-z0-9]+", key)) - {"", "the", "a", "an", "of", "for", "with"}

    def _body_part_category(self, key):
        """Identify the body-part category of an exercise for safety checks."""
        for token, category in BODY_PART_CATEGORIES.items():
            if token in key:
                return category
        return None

    def _substring_match(self, key_a, key_b):
        """
        Check if one canonical key is a meaningful substring of the other.

        Must share >= 60% of tokens to avoid false positives.
        """
        if not key_a or not key_b:
            return False

        # One must be contained in the other
        if key_a not in key_b and key_b not in key_a:
            return False

        # Safety: don't match across body-part categories
        cat_a = self._body_part_category(key_a)
        cat_b = self._body_part_category(key_b)
        if cat_a and cat_b and cat_a != cat_b:
            return False

        tokens_a = self._tokenize(key_a)
        tokens_b = self._tokenize(key_b)
        if not tokens_a or not tokens_b:
            return False

        overlap = len(tokens_a & tokens_b)
        smaller = min(len(tokens_a), len(tokens_b))
        return smaller > 0 and (overlap / smaller) >= 0.6

    def _fuzzy_match(self, key_a, key_b):
        """
        Medium-aggressive fuzzy matching using Jaccard token similarity.

        Never matches across different body-part categories.
        """
        tokens_a = self._tokenize(key_a)
        tokens_b = self._tokenize(key_b)

        if not tokens_a or not tokens_b:
            return False

        # Safety: don't match across body-part categories
        cat_a = self._body_part_category(key_a)
        cat_b = self._body_part_category(key_b)
        if cat_a and cat_b and cat_a != cat_b:
            return False

        intersection = len(tokens_a & tokens_b)
        union = len(tokens_a | tokens_b)
        if union == 0:
            return False

        jaccard = intersection / union
        return jaccard >= 0.7


# ---------------------------------------------------------------------------
# Module-level singleton for convenience
# ---------------------------------------------------------------------------
_default_normalizer = None


def get_normalizer(swaps_file="exercise_swaps.yaml"):
    """Get or create the module-level singleton normalizer."""
    global _default_normalizer
    if _default_normalizer is None:
        _default_normalizer = ExerciseNormalizer(swaps_file=swaps_file)
    return _default_normalizer


def reset_normalizer():
    """Reset the singleton (useful for testing)."""
    global _default_normalizer
    _default_normalizer = None
