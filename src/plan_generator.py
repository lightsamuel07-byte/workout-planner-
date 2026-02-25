"""
AI-powered workout plan generation using Claude API.
"""

import anthropic
import json
import os
import yaml
import re
from datetime import datetime
from src.progression_rules import (
    apply_locked_directives_to_plan,
    build_progression_directives,
    format_directives_for_prompt,
)
from src.plan_validator import validate_plan
from src.fort_compiler import repair_plan_fort_anchors, validate_fort_fidelity
from src.exercise_normalizer import get_normalizer
from src.generation_context import build_targeted_db_context


class PlanGenerator:
    """Generates intelligent workout plans using Claude AI."""

    def __init__(self, api_key, config, model=None, max_tokens=None, timeout=None):
        """
        Initialize the plan generator.

        Args:
            api_key: Anthropic API key
            config: Full configuration dictionary with athlete profile and rules
            model: Claude model to use (defaults to config value)
            max_tokens: Maximum tokens for response (defaults to config value)
            timeout: Client timeout in seconds (defaults to config value)
        """
        self.client = anthropic.Anthropic(
            api_key=api_key,
            timeout=timeout or config['claude'].get('timeout', 120)
        )
        self.model = model or config['claude']['model']
        self.max_tokens = max_tokens or config['claude']['max_tokens']
        self.config = config

    def _load_exercise_swaps(self):
        """Load exercise swaps and preferences from YAML file."""
        swaps_file = 'exercise_swaps.yaml'
        if not os.path.exists(swaps_file):
            return "No custom exercise swaps configured."

        with open(swaps_file, 'r') as f:
            swaps_config = yaml.safe_load(f)

        formatted = "**AUTOMATIC EXERCISE SWAPS:**\n"
        for original, replacement in swaps_config.get('exercise_swaps', {}).items():
            formatted += f"- {original} → {replacement}\n"

        formatted += f"\n**DAILY WARM-UP:** {swaps_config.get('daily_warmup', 'None')}\n"

        formatted += "\n**HARD PREFERENCES:**\n"
        for pref in swaps_config.get('hard_preferences', []):
            formatted += f"- {pref}\n"

        formatted += f"\n**LATERAL RAISE RULE:** {swaps_config.get('lateral_raise_rule', 'None')}\n"

        formatted += "\n**TRICEPS ATTACHMENT ROTATION:**\n"
        triceps = swaps_config.get('triceps_rules', {})
        for day, attachment in triceps.items():
            formatted += f"- {day.capitalize()}: {attachment}\n"

        formatted += "\n**BICEPS RULES (plan as a system across Tue/Thu/Sat — not day-by-day):**\n"
        for rule in swaps_config.get('biceps_rules', []):
            formatted += f"- {rule}\n"

        formatted += "\n**DELT PROGRAMMING RULES:**\n"
        for rule in swaps_config.get('delt_rules', []):
            formatted += f"- {rule}\n"

        formatted += "\n**SATURDAY-SPECIFIC RULES:**\n"
        for rule in swaps_config.get('saturday_rules', []):
            formatted += f"- {rule}\n"

        return formatted

    def _load_exercise_aliases(self):
        """Load exercise swap aliases as a name->name mapping for validators."""
        swaps_file = 'exercise_swaps.yaml'
        if not os.path.exists(swaps_file):
            return {}

        with open(swaps_file, 'r') as f:
            swaps_config = yaml.safe_load(f) or {}
        return swaps_config.get('exercise_swaps', {}) or {}

    def _select_supplemental_exercises(
        self,
        trainer_workouts,
        preferences,
        fort_compiler_context=None,
        fort_week_constraints=None,
        progression_directives_block=None,
    ):
        """
        Pass 1: Ask Claude to select exercises for Tue/Thu/Sat.

        Uses a small, cheap prompt (~800 input tokens) and requests a JSON
        array of exercise names (~200 output tokens).  The result is used
        to pull targeted DB history before the full generation call.

        Returns:
            List[str] of exercise names, or empty list on failure.
        """
        swaps_block = self._load_exercise_swaps()
        athlete_config = self._format_athlete_config_compressed()

        fort_block = ""
        if fort_compiler_context:
            fort_block = f"\nFORT CONTEXT (Mon/Wed/Fri exercises):\n{fort_compiler_context}\n"

        constraints_block = ""
        if fort_week_constraints:
            constraints_block = f"\nFORT WEEK CONSTRAINTS:\n{fort_week_constraints}\n"

        directives_block = ""
        if progression_directives_block:
            directives_block = f"\n{progression_directives_block}\n"

        prompt = f"""You are selecting supplemental exercises for Tue/Thu/Sat workout days.

{athlete_config}
{fort_block}
{constraints_block}
{directives_block}

{swaps_block}

{preferences}

TASK: List the exercise names you plan to use for Tuesday, Thursday, and Saturday.
Include ALL exercises (warm-up, main work, isolation, conditioning).
Apply exercise swap rules. Respect interference prevention rules.

Return ONLY a JSON array of exercise name strings. No explanation, no markdown.
Example: ["DB Hammer Curl", "Rope Pressdown", "15 Degree DB Chest Press", ...]
"""

        summarizer_model = (
            (self.config.get('claude', {}) or {}).get('summarizer_model')
            or self.model
        )

        try:
            message = self.client.messages.create(
                model=summarizer_model,
                max_tokens=400,
                messages=[{"role": "user", "content": prompt}],
            )
            text = (message.content[0].text or "").strip()

            # Parse JSON array from response (handle markdown fencing).
            if text.startswith("```"):
                text = re.sub(r"^```\w*\n?", "", text)
                text = re.sub(r"\n?```$", "", text)
                text = text.strip()

            exercises = json.loads(text)
            if isinstance(exercises, list):
                return [str(e).strip() for e in exercises if e]
        except (json.JSONDecodeError, IndexError, Exception) as exc:
            print(f"  Exercise selection pass failed ({exc}), falling back to full context.")

        return []

    def generate_plan(
        self,
        workout_history,
        trainer_workouts,
        preferences,
        fort_week_constraints=None,
        fort_compiler_context=None,
        fort_compiler_meta=None,
        db_context=None,
        db_path=None,
        prior_supplemental=None,
    ):
        """
        Generate a weekly workout plan using Claude AI.

        Uses two-pass generation when db_path is provided:
          Pass 1: Claude selects exercises for Tue/Thu/Sat (cheap, ~200 output tokens).
          DB lookup: Pull history only for selected exercises.
          Pass 2: Full plan generation with targeted exercise history.

        Args:
            workout_history: Formatted string of recent workout history
            trainer_workouts: Formatted string of trainer workouts
            preferences: Formatted string of user preferences
            db_path: Path to SQLite DB for two-pass targeted context.

        Returns:
            Generated workout plan as string
        """
        print("\n🤖 Generating your personalized workout plan with Claude AI...")

        progression_directives = build_progression_directives(prior_supplemental)
        directives_block = format_directives_for_prompt(progression_directives)

        # ── Two-pass: exercise selection → targeted DB lookup ───────
        if db_path and os.path.exists(db_path):
            selected_exercises = self._select_supplemental_exercises(
                trainer_workouts=trainer_workouts,
                preferences=preferences,
                fort_compiler_context=fort_compiler_context,
                fort_week_constraints=fort_week_constraints,
                progression_directives_block=directives_block,
            )
            if selected_exercises:
                targeted_context = build_targeted_db_context(
                    db_path,
                    exercise_names=selected_exercises,
                    logs_per_exercise=4,
                    max_chars=3200,
                )
                if targeted_context:
                    db_context = targeted_context
                    print(f"  Two-pass: {len(selected_exercises)} exercises selected, DB context built.")

        # Construct the prompt
        prompt = self._build_prompt(
            workout_history,
            trainer_workouts,
            preferences,
            fort_week_constraints=fort_week_constraints,
            fort_compiler_context=fort_compiler_context,
            db_context=db_context,
            progression_directives_block=directives_block,
        )

        try:
            # Call Claude API
            message = self.client.messages.create(
                model=self.model,
                max_tokens=self.max_tokens,
                messages=[
                    {
                        "role": "user",
                        "content": prompt
                    }
                ]
            )

            plan = message.content[0].text
            plan = self._apply_exercise_swaps_to_text(plan)
            plan = self._enforce_even_dumbbell_loads(plan)
            plan, locked_applied = apply_locked_directives_to_plan(plan, progression_directives)
            exercise_aliases = self._load_exercise_aliases()
            total_anchor_insertions = 0

            # Deterministic range collapse and deterministic repairs happen before any correction call.
            plan, range_violations, range_collapsed = self._validate_no_ranges(plan, attempt=2)
            plan = self._repair_plan_deterministically(plan, progression_directives)
            plan, anchor_repair = repair_plan_fort_anchors(
                plan,
                fort_compiler_meta,
                exercise_aliases=exercise_aliases,
            )
            total_anchor_insertions += anchor_repair.get("inserted", 0)
            plan = self._canonicalize_exercise_names(plan)
            validation = validate_plan(plan, progression_directives)
            fort_fidelity = validate_fort_fidelity(
                plan,
                fort_compiler_meta,
                exercise_aliases=exercise_aliases,
            )

            unresolved_violations = validation["violations"] + fort_fidelity["violations"]
            correction_attempts = 0
            max_correction_attempts = 2
            while unresolved_violations and correction_attempts < max_correction_attempts:
                correction_prompt = self._build_correction_prompt(
                    plan,
                    unresolved_violations,
                    fort_compiler_context=fort_compiler_context,
                    fort_fidelity_summary=fort_fidelity.get("summary"),
                )
                message2 = self.client.messages.create(
                    model=self.model,
                    max_tokens=5000,  # correction only needs to reproduce the plan, not expand it
                    messages=[
                        {"role": "user", "content": correction_prompt}
                    ]
                )
                plan = message2.content[0].text
                plan = self._apply_exercise_swaps_to_text(plan)
                plan = self._repair_plan_deterministically(plan, progression_directives)
                plan, anchor_repair = repair_plan_fort_anchors(
                    plan,
                    fort_compiler_meta,
                    exercise_aliases=exercise_aliases,
                )
                total_anchor_insertions += anchor_repair.get("inserted", 0)
                plan = self._canonicalize_exercise_names(plan)

                validation = validate_plan(plan, progression_directives)
                fort_fidelity = validate_fort_fidelity(
                    plan,
                    fort_compiler_meta,
                    exercise_aliases=exercise_aliases,
                )
                unresolved_violations = validation["violations"] + fort_fidelity["violations"]
                correction_attempts += 1

            validation_summary = (
                f"{validation['summary']} {fort_fidelity['summary']} "
                f"Locked directives applied: {locked_applied}. "
                f"Fort anchors auto-inserted: {total_anchor_insertions}. "
                f"Correction attempts: {correction_attempts}. "
                f"Unresolved violations: {len(unresolved_violations)}."
            )

            # Generate explanation file
            explanation = self._generate_explanation(
                plan,
                workout_history,
                violations_collapsed=range_violations if range_collapsed else None,
                validation_summary=validation_summary,
                fort_fidelity_summary=fort_fidelity["summary"],
                unresolved_violations=unresolved_violations,
                anchor_insertions=total_anchor_insertions,
            )

            print("✓ Workout plan generated successfully!\n")
            return plan, explanation, validation_summary

        except Exception as e:
            print(f"Error generating plan: {e}")
            return None, None, None

    def summarize_fort_preamble(self, preamble_text):
        if not preamble_text or not preamble_text.strip():
            return None

        prompt = f"""Summarize the following Fort week/program preamble into concise constraints for programming.

Output rules:
- 6-12 bullet points max.
- Only include actionable constraints (clusters, rest intervals, progression intent, rep scheme changes, load guidance, fatigue intent).
- Preserve key numeric details.
- No tables.

PREAMBLE:
{preamble_text}
"""

        summarizer_model = (
            (self.config.get('claude', {}) or {}).get('summarizer_model')
            or self.model
        )

        try:
            message = self.client.messages.create(
                model=summarizer_model,
                max_tokens=300,
                messages=[
                    {"role": "user", "content": prompt}
                ]
            )
            text = message.content[0].text
            return text.strip() if text else None
        except Exception as e:
            print(f"Error summarizing Fort preamble: {e}")
            return None

    def _apply_exercise_swaps_to_text(self, text):
        swaps_file = 'exercise_swaps.yaml'
        if not os.path.exists(swaps_file):
            return text

        with open(swaps_file, 'r') as f:
            swaps_config = yaml.safe_load(f) or {}

        swaps = swaps_config.get('exercise_swaps', {}) or {}
        for original, replacement in swaps.items():
            if not original or not replacement:
                continue
            pattern = re.compile(re.escape(str(original)), re.IGNORECASE)
            text = pattern.sub(str(replacement), text)

        return text

    def _enforce_even_dumbbell_loads(self, text):
        """
        Enforce even-number dumbbell loads only.
        Any DB exercise prescription like "@ 7 kg" will be coerced to an even load.
        Tie behavior (exact odd integers) is conservative: rounds down (7 -> 6).
        """
        lines = text.split('\n')
        current_is_db = False
        current_is_main_lift = False
        header_re = re.compile(r'^\s*###\s+[A-Z]\d+\.\s*(.+)$', re.IGNORECASE)
        load_re = re.compile(r'@\s*([\d]+(?:\.\d+)?)\s*kg\b', re.IGNORECASE)

        def is_main_plate_lift(exercise_name):
            normalized = re.sub(r"[^a-z0-9]+", " ", (exercise_name or "").lower()).strip()
            is_db = (' db ' in f' {normalized} ') or ('dumbbell' in normalized)
            if is_db:
                return False
            return any(
                token in normalized
                for token in ['back squat', 'front squat', 'deadlift', 'bench press', 'chest press']
            )

        def coerce_even(value):
            rounded = int(round(value))
            if rounded % 2 == 0:
                return rounded

            lower_even = rounded - 1
            upper_even = rounded + 1
            if abs(value - lower_even) <= abs(value - upper_even):
                return lower_even
            return upper_even

        for i, line in enumerate(lines):
            header_match = header_re.match(line.strip())
            if header_match:
                exercise_name = header_match.group(1).lower()
                current_is_db = ('db' in exercise_name) or ('dumbbell' in exercise_name)
                current_is_main_lift = is_main_plate_lift(exercise_name)
                continue

            if not current_is_db or current_is_main_lift:
                continue

            if '@' not in line or 'kg' not in line.lower():
                continue

            def repl(match):
                raw = float(match.group(1))
                even_load = coerce_even(raw)
                return f"@ {even_load} kg"

            lines[i] = load_re.sub(repl, line)

        return '\n'.join(lines)

    def _validate_no_ranges(self, text, attempt=1):
        """
        Validate that the plan contains no rep or load ranges in the
        exercise prescription line only (the line that looks like:
        "- 4 x 12 @ 24 kg").

        This intentionally allows Fort narrative ranges like "rest 25–30s"
        or "rep schemes 8/12/15" in notes.
        Hybrid policy: retry once, then auto-collapse if still failing.
        Returns: (validated_text, violations_found, was_collapsed)
        """
        # Pattern to match numeric ranges like "12-15" or "25–30"
        range_pattern = re.compile(r'(\d+)\s*[-–]\s*(\d+)')
        violations = []

        lines = text.split('\n')
        for i, line in enumerate(lines):
            stripped = line.strip()
            # Only enforce on the exercise prescription line.
            # Example: "- 4 x 12 @ 24 kg" (also works for timed lines "- 1 x 10:00 @ 3.4 mph")
            if not stripped.startswith('-'):
                continue
            if ' x ' not in stripped:
                continue
            if '@' not in stripped:
                continue

            matches = range_pattern.findall(stripped)
            for match in matches:
                violations.append((i + 1, stripped, match))

        if not violations:
            return text, [], False

        # If this is first attempt, return violations for retry
        if attempt == 1:
            return text, violations, False

        # Auto-collapse: reps -> top value, load -> midpoint (only within prescription lines)
        collapsed_text = text
        collapsed_lines = collapsed_text.split('\n')
        for line_num, line, (low, high) in violations:
            idx = line_num - 1
            if idx < 0 or idx >= len(collapsed_lines):
                continue

            current = collapsed_lines[idx]
            stripped = current.strip()
            if not stripped.startswith('-') or ' x ' not in stripped or '@' not in stripped:
                continue

            low_val, high_val = int(low), int(high)

            # If the range occurs after '@', treat as load; otherwise treat as reps.
            at_pos = stripped.find('@')
            range_pos = stripped.find(f"{low}")
            if at_pos != -1 and range_pos != -1 and range_pos > at_pos:
                midpoint = (low_val + high_val) / 2.0
                replacement = f"{midpoint:.1f}".rstrip("0").rstrip(".")
            else:
                replacement = str(high_val)

            # Replace first occurrence of the specific range token in that line.
            current = re.sub(rf"\b{re.escape(low)}\s*[-–]\s*{re.escape(high)}\b", replacement, current, count=1)
            collapsed_lines[idx] = current

        collapsed_text = "\n".join(collapsed_lines)

        return collapsed_text, violations, True

    def _generate_explanation(
        self,
        plan,
        workout_history,
        violations_collapsed=None,
        validation_summary=None,
        fort_fidelity_summary=None,
        unresolved_violations=None,
        anchor_insertions=0,
    ):
        """Generate short explanation file (5-15 bullets)."""
        bullets = []

        # Basic stats
        lines = plan.split('\n')
        exercise_count = sum(1 for l in lines if l.strip().startswith('###'))
        bullets.append(f"Total exercises: {exercise_count}")

        # Progressive overload summary
        if workout_history and 'supplemental' in workout_history.lower():
            bullets.append("Progressive overload applied based on prior week performance")

        # Any swaps applied
        swaps_file = 'exercise_swaps.yaml'
        if os.path.exists(swaps_file):
            with open(swaps_file, 'r') as f:
                swaps_config = yaml.safe_load(f) or {}
            swaps = swaps_config.get('exercise_swaps', {})
            if swaps:
                bullets.append(f"Exercise swaps enforced: {len(swaps)} rules active")

        # Hard preferences
        bullets.append("Standing calf raises only (no seated)")
        bullets.append("No belt on pulls/deadlifts")
        bullets.append("Biceps grip rotation: supinated → neutral → pronated")

        # Range violations handled
        if violations_collapsed:
            bullets.append(f"Auto-corrected {len(violations_collapsed)} range violations to single values")

        if validation_summary:
            bullets.append(validation_summary)
        elif fort_fidelity_summary:
            bullets.append(fort_fidelity_summary)

        if anchor_insertions:
            bullets.append(f"Auto-inserted {anchor_insertions} missing Fort anchor exercises before final validation")

        unresolved_count = len(unresolved_violations or [])
        if unresolved_count:
            bullets.append(f"Remaining violations after repair/correction: {unresolved_count}")

        # Focus areas
        bullets.append("Focus: arms, medial delts, upper chest, back detail")
        bullets.append("Incline walking included on all supplemental days")

        return "\n".join(f"• {b}" for b in bullets[:15])  # Cap at 15 bullets

    def _repair_plan_deterministically(self, text, progression_directives):
        """Apply deterministic post-generation repairs."""
        repaired = self._enforce_even_dumbbell_loads(text)
        repaired, _ = apply_locked_directives_to_plan(repaired, progression_directives)
        repaired, _, _ = self._validate_no_ranges(repaired, attempt=2)
        return repaired

    def _canonicalize_exercise_names(self, plan_text):
        """
        Replace exercise names in the plan with their canonical display forms.

        Parses ### A1. Exercise Name lines and replaces non-canonical names.
        """
        if not plan_text:
            return plan_text

        normalizer = get_normalizer()
        exercise_header_re = re.compile(r"^(\s*###\s+[A-Z]\d+\.\s*)(.+)$", re.IGNORECASE)
        lines = plan_text.split("\n")

        for idx, line in enumerate(lines):
            match = exercise_header_re.match(line)
            if not match:
                continue

            prefix = match.group(1)
            raw_name = match.group(2).strip()
            canonical = normalizer.canonical_name(raw_name)

            if canonical and canonical != raw_name:
                lines[idx] = f"{prefix}{canonical}"

        return "\n".join(lines)

    def _build_correction_prompt(
        self,
        plan,
        violations,
        fort_compiler_context=None,
        fort_fidelity_summary=None,
    ):
        """Build compact correction prompt from unresolved validator violations."""
        lines = []
        for violation in violations[:20]:
            day = violation.get("day") or "Unknown day"
            exercise = violation.get("exercise") or "Unknown exercise"
            message = violation.get("message", "")
            lines.append(f"- {violation['code']} | {day} | {exercise} | {message}")

        fort_context_block = ""
        if fort_compiler_context:
            fort_context_block = f"\nFORT COMPILER DIRECTIVES:\n{fort_compiler_context}\n"

        fort_summary_block = ""
        if fort_fidelity_summary:
            fort_summary_block = f"\nCurrent fort fidelity status: {fort_fidelity_summary}\n"

        return f"""Correct this workout plan to satisfy all listed validation violations.

Violations:
{chr(10).join(lines)}

{fort_summary_block}

{fort_context_block}

Hard requirements:
- Keep overall structure and exercise order unless violation requires change.
- Preserve Fort day content and supplemental intent.
- Keep no-range rule in prescription lines.
- Keep dumbbell parity rule (even DB loads, except main barbell lifts).
- Respect explicit keep/stay-here progression constraints from prior logs.
- Never emit section labels or instructional lines as exercises (examples: "Targeted Warm-Up", "1RM Test", "Back-offs", "TIPS", "Rest 2 minutes", "Right into").

Return the full corrected plan in the same markdown format.

PLAN:
{plan}
"""

    def _build_prompt(
        self,
        workout_history,
        trainer_workouts,
        preferences,
        fort_week_constraints=None,
        fort_compiler_context=None,
        db_context=None,
        progression_directives_block=None,
    ):
        """
        Build the AI prompt for plan generation using compressed format.

        Args:
            workout_history: Formatted workout history
            trainer_workouts: Formatted trainer workouts
            preferences: Formatted user preferences

        Returns:
            Complete prompt string
        """
        # Extract athlete profile and rules from config
        athlete_config = self._format_athlete_config_compressed()

        fort_constraints_block = ""
        if fort_week_constraints:
            fort_constraints_block = f"\nFORT WEEK CONSTRAINTS:\n{fort_week_constraints}\n"

        fort_compiler_block = ""
        if fort_compiler_context:
            fort_compiler_block = f"\n{fort_compiler_context}\n\n---\n"

        db_context_block = ""
        if db_context:
            db_context_block = f"\n{db_context}\n\n---\n"

        directives_block = ""
        if progression_directives_block:
            directives_block = f"\n{progression_directives_block}\n\n---\n"

        prompt = f"""You are an expert strength and conditioning coach generating a complete weekly workout plan for {self.config['athlete']['name']}.

CRITICAL OUTPUT RULE: NO RANGES anywhere in prescription lines. Use single values only.
  ✓ "15 reps" / "24 kg" — CORRECT
  ✗ "12-15 reps" / "22-26 kg" — FORBIDDEN (will be rejected)

{athlete_config}

{fort_constraints_block}

---

{fort_compiler_block}

{workout_history}

---

{db_context_block}

{directives_block}

================================================================================
FORT WORKOUT CONVERSION (Mon/Wed/Fri)
================================================================================
The Fort workouts below come from TrainHeroic in raw copy-paste format. Convert each to the standard exercise format. Rules:

1. STRUCTURE: If FORT COMPILER DIRECTIVES are present, treat section order and anchor exercises as hard constraints. Preserve block order A→B→C→D→E→F exactly.

2. EXTRACT ALL EXERCISES: Include every exercise from every section — PREP/IGNITION, WARM-UP, POWER, CLUSTER WARM-UP, CLUSTER SET SINGLES, CLUSTER SET DOUBLES, WORKING SET, BREAKPOINT, BACK-OFFS, AUXILIARY/MYO, CIRCUIT/THAW/REDEMPTION.

3. LOAD CALCULATION: Convert all percentage-based loads to actual kg using the 1RMs below.
   - If Fort defines "training max" or "working max" in coach notes (e.g., "use 90% of your 1RM as training max"), apply that definition first, then calculate set percentages from it.
   - Round all barbell loads to nearest 2.5 kg.
   - Example: 85% × 94 kg bench = 79.9 → round to 80 kg.

4. CLUSTER SETS: Format cluster set singles as individual prescription lines where each "set" is one cluster rep.
   - Example: 6 cluster singles at 85% bench → 6 x 1 @ 80 kg

5. FORBIDDEN AS EXERCISE NAMES: Never output section headers or instructional text as exercise names.
   Forbidden: "Targeted Warm-Up", "Back-offs", "TIPS", "HISTORY", "COMPLETE", "Rest 2 minutes", "Right into", "Rx", "Weight", "Reps", "Meters", "Calories"

6. NOTES FIELD ONLY: All coaching context (technique cues, intensity targets, cluster instructions, myo-rep protocols) goes in the Notes field — not in separate fields.

7. CIRCUIT/GARAGE: When Fort offers location options (Underground / Garage), always use the Garage version.

CONCRETE EXAMPLE — Fort input → correct output:
  Input: "CLUSTER SET SINGLES / BENCH PRESS / 6 Sets / 85%, 6 reps"
  Output:
  ### C1. Bench Press (Cluster Singles)
  - 6 x 1 @ 80 kg
  - **Rest:** 25-30 sec intra-cluster, 3 min after final rep
  - **Notes:** Un-rack for a fresh rep every 25-30 sec. Max bar speed each rep. 85% of 94 kg bench = 80 kg.

{trainer_workouts}

---

{preferences}

---

================================================================================
SUPPLEMENTAL DAYS (Tue/Thu/Sat) — AESTHETIC HYPERTROPHY
================================================================================
These are the growth sessions. Every exercise must serve the aesthetic objective: arms, medial delts, upper chest, back detail. If an exercise doesn't directly serve one of those four priorities, it shouldn't be there.

STRUCTURE FOR ALL THREE SUPPLEMENTAL DAYS:
  A-block: McGill Big-3 warm-up (always — 1 set each: curl-up, side-bridge, bird-dog)
  B-block: Main hypertrophy work (2-4 exercises targeting the day's priority muscles)
  C/D-block: Secondary hypertrophy (2-3 exercises, complementary muscle groups)
  E-block: Isolation finishers (1-2 exercises, high-rep, short rest)
  F-block: Incline walk — Tuesday & Thursday: 10 min @ 3.4 kph, 8% incline | Saturday: 15 min @ 3.5 kph, 6% incline

TUESDAY priority: Arms (biceps + triceps) + medial/rear delts. Carries go here if programmed.
THURSDAY priority: Medial delts + upper chest (incline pressing) + back detail. Keep grip load low.
SATURDAY priority: Arms (different grip/attachment from Tuesday/Thursday) + upper chest + rear delts.

PROGRESSIVE OVERLOAD — HOW TO READ LOGS AND PROGRESS:

Read prior logged performance from the EXERCISE HISTORY and PROGRESSION DIRECTIVES above.

Signal classification:
  STRUGGLED: "felt heavy", "quite heavy", "struggled", "tough", "challenging", "failed", RPE ≥ 9.0
    → DO NOT increase load or reps. Hold same prescription. If failed, consider slight reduction.
  EXCEEDED: "easy", "too light", "could do more", "had reps left", "fly", RPE ≤ 7.0
    → Increase EITHER reps by 1-2 OR load by one step. NEVER both in the same week.
  NEUTRAL (no qualifier, or RPE 7.5-8.5): hit the target cleanly
    → DBs: increase load by next even increment (e.g., 10→12 kg). Cables: add one plate. Keep reps same.

Conflict rule: When log text and RPE conflict, text wins. Use RPE only to size the adjustment.
  Example: "felt heavy (RPE 7.5)" → text=struggled wins → hold load, don't progress.

NEVER increase both reps AND load in the same week.

MANDATORY HARD RULES (enforced post-generation — violations trigger correction):
• No ranges in prescription lines (single values only)
• DB loads: even numbers only (2 kg increments)
• No split squats (any variant) — replace with heel-elevated goblet squat or leg extension
• Standing calves only — never seated calf raises
• No belt on pulls
• Biceps: never same grip on consecutive supplemental days | rotate sup→neutral→pron | ≤12 hard sets/rolling 4 days | ≥48h between long-length stimuli
• Triceps: rope on Tuesday, straight-bar on Friday, no single-arm D-handle on Saturday
• Carries: Tuesday only, RPE 6-7 max (grip protection for Friday deadlift)

EXERCISE FORMAT (identical for all days):
### A1. [Exercise Name]
- [Sets] x [Reps] @ [Load] kg
- **Rest:** [period]
- **Notes:** [Coaching cues, technique, progression context — 1-2 sentences max.]

NAMING RULES:
• DB pressing: always specify angle (e.g., "30° Incline DB Press")
• Cable exercises with dual cables: state load per side
• Carries: always kettlebell (never dumbbell)
• Calves: always "Standing" in the name

REST PERIODS:
• Fort main lifts: 3-5 min | Fort compounds: 2-3 min | Fort isolation: 60-90 sec
• Supplemental compounds: 90-120 sec | Supplemental isolation: 60-90 sec | Finishers: 30-45 sec

1RMs: Squat 129 kg | Bench Press 94 kg | Deadlift 168 kg

================================================================================
OUTPUT FORMAT
================================================================================
Use ## MONDAY, ## TUESDAY, etc. headers.
Use ### A1., ### A2., ### B1. etc. exercise labels.
American spelling throughout.
End the plan with a brief SANITY CHECK confirming:
  - Biceps grip used each supplemental day (and that no consecutive days repeat)
  - Triceps attachment used each day (Tue/Fri/Sat)
  - No interference rule violations
  - No hard rule violations

Generate the complete weekly plan now."""

        return prompt

    def _format_athlete_config_compressed(self):
        """Format the athlete configuration section for the prompt."""
        return f"""
ATHLETE: {self.config['athlete']['name']} | {self.config['athlete']['units']} | {self.config['athlete']['spelling']} spelling
SCHEDULE: Fort Mon/Wed/Fri | Supplemental Tue/Thu/Sat

AESTHETIC OBJECTIVE (the entire point of Tue/Thu/Sat):
Samuel's goal is a strength-first, visibly muscular physique. Think broader shoulders, bigger arms, upper-chest shelf, upper-back density. Priority order for supplemental volume:
  1. Arms — biceps shape + triceps fullness (HIGH priority)
  2. Delts — medial delt cap for width, rear delt for 3D look (HIGH priority)
  3. Upper chest — clavicular pec "pop", incline pressing/fly patterns (HIGH priority)
  4. Back detail — upper-back density, rear-delt tie-in, posture (HIGH priority)
  5. Everything else is secondary and must not crowd out the above.

Supplemental days exist to grow these muscle groups — NOT to be generic fitness sessions.
Aesthetics cannot blunt main-lift performance. Stimulus-efficient hypertrophy: enough volume to grow, not so much fatigue that Mon/Wed/Fri bar speed suffers.

INTERFERENCE PREVENTION (strict — defines what is forbidden on each supplemental day):
• Tuesday (after Monday squat, before Wednesday bench):
  - ALLOWED: arm isolation, medial/rear delt work, upper-chest pressing (moderate), back detail, carries
  - FORBIDDEN: any leg compounds, barbell pressing, heavy front-delt loading, anything that crushes Wednesday bench
  - "Heavy" = RPE > 7 on pressing movements, or any barbell chest/shoulder pressing
• Thursday (after Wednesday bench, before Friday deadlift):
  - ALLOWED: light leg isolation (leg extension, leg curl — NOT leg press or squats), chest isolation, delt isolation, light upper back
  - FORBIDDEN: heavy grip work (no loaded carries), heavy rows, heavy bicep volume (>6 hard sets), anything that compromises Friday deadlift setup or grip
  - "Heavy grip" = any loaded carry, heavy cable rows, heavy DB rows exceeding RPE 7
• Saturday (after Friday deadlift, before Monday squat):
  - ALLOWED: upper body only — arms, delts, upper chest, upper back
  - FORBIDDEN: heavy lower back compounds, heavy leg work, junk volume with no aesthetic payoff
  - Spinal fatigue must be minimal going into Sunday rest → Monday squat

HARD RULES (absolute — violations require correction):
Equipment: {' | '.join(self.config['hard_rules']['equipment'])}
DB loads: Even numbers only (2 kg increments — never odd-kg DB loads)
Biceps grip rotation: Never same grip on consecutive supplemental days | Rotate sup → neutral → pron | ≤12 hard sets per rolling 4 days | ≥48h between long-length stimuli (e.g., incline curls)
Triceps: Vary attachment across Tue/Fri/Sat (rope Tue, straight-bar Fri, varied Sat) | No single-arm D-handle on Saturday
Carries: Tuesday only, moderate load (RPE 6-7 max) to preserve Friday deadlift grip
Calves: Standing only — if any seated calf exercise appears, replace with standing variant

LOAD ROUNDING RULES:
• Barbell: round to nearest 0.5 kg (microplates available — e.g., 79.9 → 80 kg, 82.3 → 82.5 kg)
• Dumbbell: round to nearest 2 kg, even numbers only (e.g., 11 → 12 kg, 13 → 14 kg)
• Cable: use load from history or a sensible round number — no fixed increment, cable stacks vary by machine
• Percentage-based Fort loads: compute from 1RM or training max, then round to nearest 0.5 kg
• Training max / working max: if Fort coach notes define it (e.g., "use 90% of your 1RM as training max"), apply that definition first, then calculate set percentages from it"""

    def save_plan(self, plan, explanation=None, output_folder="output", format="markdown"):
        """
        Save the generated plan and optional explanation to files.

        Args:
            plan: The generated plan text
            explanation: The explanation text (optional)
            output_folder: Folder to save the plan
            format: File format (markdown, text, json)

        Returns:
            Tuple of (plan_path, explanation_path or None)
        """
        if not plan:
            print("No plan to save.")
            return None, None

        # Create output folder if it doesn't exist
        os.makedirs(output_folder, exist_ok=True)

        # Generate filename with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        extension = "md" if format == "markdown" else "txt"

        # Save main plan
        filename = f"workout_plan_{timestamp}.{extension}"
        filepath = os.path.join(output_folder, filename)
        with open(filepath, 'w') as f:
            f.write(plan)
        print(f"✓ Plan saved to: {filepath}")

        # Save explanation if provided
        expl_path = None
        if explanation:
            expl_filename = f"workout_plan_{timestamp}_explanation.{extension}"
            expl_path = os.path.join(output_folder, expl_filename)
            with open(expl_path, 'w') as f:
                f.write(explanation)
            print(f"✓ Explanation saved to: {expl_path}")

        return filepath, expl_path
