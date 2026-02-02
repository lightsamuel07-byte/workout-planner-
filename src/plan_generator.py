"""
AI-powered workout plan generation using Claude API.
"""

import anthropic
import os
import yaml
import re
from datetime import datetime


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

        formatted += "\n**BICEPS RULES:**\n"
        for rule in swaps_config.get('biceps_rules', []):
            formatted += f"- {rule}\n"

        return formatted

    def generate_plan(self, workout_history, trainer_workouts, preferences, fort_week_constraints=None):
        """
        Generate a weekly workout plan using Claude AI.

        Args:
            workout_history: Formatted string of recent workout history
            trainer_workouts: Formatted string of trainer workouts
            preferences: Formatted string of user preferences

        Returns:
            Generated workout plan as string
        """
        print("\n🤖 Generating your personalized workout plan with Claude AI...")

        # Construct the prompt
        prompt = self._build_prompt(workout_history, trainer_workouts, preferences, fort_week_constraints=fort_week_constraints)

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

            # Validate and enforce no ranges (hybrid: retry once, then collapse)
            plan, violations, was_collapsed = self._validate_no_ranges(plan, attempt=1)
            if violations and not was_collapsed:
                # Lightweight retry: just send the plan + specific corrections (no full context)
                correction_prompt = f"""Fix these {len(violations)} range violations in the workout plan below:

{chr(10).join(f"• {v[1]}: {v[2][0]}-{v[2][1]} (use higher value for reps, midpoint for load)" for v in violations[:15])}

Rules:
- Reps ranges (e.g., 12-15): use HIGHER value → 15
- Load ranges (e.g., 22-26 kg): use MIDPOINT → 24 kg

Return ONLY the corrected lines in the same format. Here's the full plan to fix:

{plan}"""
                message2 = self.client.messages.create(
                    model=self.model,
                    max_tokens=self.max_tokens,
                    messages=[
                        {"role": "user", "content": correction_prompt}
                    ]
                )
                plan = message2.content[0].text
                plan = self._apply_exercise_swaps_to_text(plan)
                plan, violations, was_collapsed = self._validate_no_ranges(plan, attempt=2)

            # Generate explanation file
            explanation = self._generate_explanation(plan, workout_history, violations if was_collapsed else None)

            print("✓ Workout plan generated successfully!\n")
            return plan, explanation

        except Exception as e:
            print(f"Error generating plan: {e}")
            return None, None

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
                replacement = str(int(round((low_val + high_val) / 2.0)))
            else:
                replacement = str(high_val)

            # Replace first occurrence of the specific range token in that line.
            current = re.sub(rf"\b{re.escape(low)}\s*[-–]\s*{re.escape(high)}\b", replacement, current, count=1)
            collapsed_lines[idx] = current

        collapsed_text = "\n".join(collapsed_lines)

        return collapsed_text, violations, True

    def _generate_explanation(self, plan, workout_history, violations_collapsed=None):
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

        # Focus areas
        bullets.append("Focus: arms, medial delts, upper chest, back detail")
        bullets.append("Incline walking included on all supplemental days")

        return "\n".join(f"• {b}" for b in bullets[:15])  # Cap at 15 bullets

    def _build_prompt(self, workout_history, trainer_workouts, preferences, fort_week_constraints=None):
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

        prompt = f"""You are an expert strength and conditioning coach creating a personalized weekly workout plan for {self.config['athlete']['name']}.

CRITICAL: NO RANGES - use single values only (e.g., "15 reps" not "12-15", "24 kg" not "22-26 kg")

{athlete_config}

{fort_constraints_block}

---

{workout_history}

---

FORT WORKOUT CONVERSION (CRITICAL):
The Fort workouts below (Mon/Wed/Fri) are from Train Heroic in raw format. You MUST convert them to the standardized ### A1. Exercise format:
  * Extract ALL exercises from these sections: PREP (mobility/warmup), CLUSTER WARM-UP (progressive warmup sets), primary cluster work (singles/doubles), MYO REP finishers (accessories), THAW (conditioning circuits)
  * Convert each to the ### A1. [Exercise Name] format shown below with complete details (sets x reps @ load, rest period)
  * Add coaching context: RPE (effort 1-10), Form (technique cues), Energy (intensity level), Adjustments (modifications), Notes (programming rationale)
  * Keep original block labels intact (A1-A4=PREP, B1-B5=warmup, C1/D1=main clusters, E1-E3=accessories, F1=THAW)
  * Calculate actual kg loads from percentages if specified (1RMs listed below)

{trainer_workouts}

---

{preferences}

---

CORE PRINCIPLES:
- Supplemental days (Tue/Thu/Sat) support Fort work - focus: arms, medial delts, upper chest, back detail
- Progressive overload: +2.5-5kg if user exceeded reps, maintain if struggled, +2.5kg if exact
- SWAP directives from logs are HARD constraints - replace as requested, don't progress

FOR SUPPLEMENTAL DAYS - INTERFERENCE PREVENTION:
Tue (post-squat/pre-press): Arms, shoulders, upper chest, back detail only. NO heavy legs/pressing
Thu (post-press/pre-deadlift): Light legs, chest, delts only. NO heavy biceps/grip work  
Sat (post-deadlift): Upper body only. NO heavy lower back/leg compounds

MANDATORY HARD RULES:
• Equipment: No belt on pulls, standing calves only, no split squats
• Biceps: Rotate grips (sup→neutral→pron), never same grip consecutive days, ≤12 sets/4days
• Triceps: Vary attachments Tue/Fri/Sat, no single-arm D-handle Sat
• Carries: Tuesday only, RPE 6-7 (preserve Friday grip)
• Daily: McGill Big-3 warm-up, incline walking (10min@3.4mph/6%, 15min@3.5mph/6%)

EXERCISE FORMAT (ALL EXERCISES):
### A1. [Exercise Name]
- [Sets] x [Reps] @ [Load] kg
- **Rest:** [period]
- **RPE:** [target]
- **Form:** [cues]
- **Energy:** [level]
- **Adjustments:** [mods]
- **Notes:** [coaching]

NAMING RULES:
• Bench: specify angle (e.g., "30° Incline DB Press")
• Cable dual: load per side
• Carries: use kettlebells

REST PERIODS:
• Fort main lifts: 3-5min, compounds: 2-3min, isolation: 60-90s
• Supplemental main: 90-120s, isolation: 60-90s, finishers: 30-45s

1RMs: Squat 129kg, Bench 94kg, Deadlift 168kg

OUTPUT: Use ## day headers, ### exercise format, American spelling. Include sanity check confirmation.

Generate complete weekly plan following ALL rules above."""

        return prompt

    def _format_athlete_config_compressed(self):
        """Format the athlete configuration section for the prompt in compressed format."""
        return f"""
ATHLETE: {self.config['athlete']['name']} | {self.config['athlete']['units']} | {self.config['athlete']['spelling']} spelling
GOAL: {self.config['goals']['primary']} | Focus: {', '.join(self.config['goals']['focus_areas'])}
SCHEDULE: Fort {', '.join(self.config['weekly_structure']['main_days'])} | Supplemental {', '.join(self.config['weekly_structure']['supplemental_days'])}
HARD RULES: {' | '.join(self.config['hard_rules']['equipment'])} | Biceps: {' | '.join(self.config['hard_rules']['biceps'])}"""

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
