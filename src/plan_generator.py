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

    def __init__(self, api_key, config, model=None, max_tokens=None):
        """
        Initialize the plan generator.

        Args:
            api_key: Anthropic API key
            config: Full configuration dictionary with athlete profile and rules
            model: Claude model to use (defaults to config value)
            max_tokens: Maximum tokens for response (defaults to config value)
        """
        self.client = anthropic.Anthropic(api_key=api_key)
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

            missing_days = self._missing_required_days(plan)
            if missing_days:
                correction_prompt = (
                    "Your previous output is INCOMPLETE. You must return a COMPLETE weekly plan.\n\n"
                    "Requirements:\n"
                    "- Include sections for every day: MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY, SUNDAY.\n"
                    "- Each day must start with a markdown header like: ## MONDAY ...\n"
                    "- Preserve the Fort days exactly, and add supplemental days around them.\n"
                    "- Return the COMPLETE corrected plan only.\n\n"
                    f"Missing day sections: {', '.join(missing_days)}"
                )
                message_fix = self.client.messages.create(
                    model=self.model,
                    max_tokens=self.max_tokens,
                    messages=[
                        {"role": "user", "content": prompt},
                        {"role": "assistant", "content": plan},
                        {"role": "user", "content": correction_prompt},
                    ],
                )
                plan = message_fix.content[0].text
                plan = self._apply_exercise_swaps_to_text(plan)

                missing_days = self._missing_required_days(plan)
                if missing_days:
                    raise ValueError(f"Generated plan is incomplete. Missing day sections: {', '.join(missing_days)}")

            # Validate and enforce no ranges (hybrid: retry once, then collapse)
            plan, violations, was_collapsed = self._validate_no_ranges(plan, attempt=1)
            if violations and not was_collapsed:
                # Retry once with correction prompt
                correction_prompt = f"""The previous plan had range values. Fix these to single values:
{chr(10).join(f"Line {v[0]}: {v[2][0]}-{v[2][1]} -> pick single value" for v in violations[:10])}

Rules:
- Reps: use the HIGHER value (e.g., 12-15 -> 15)
- Load (kg): use the MIDPOINT (e.g., 22-26 -> 24)

Return the COMPLETE corrected plan."""
                message2 = self.client.messages.create(
                    model=self.model,
                    max_tokens=self.max_tokens,
                    messages=[
                        {"role": "user", "content": prompt},
                        {"role": "assistant", "content": plan},
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

    def _missing_required_days(self, text):
        required = [
            'MONDAY',
            'TUESDAY',
            'WEDNESDAY',
            'THURSDAY',
            'FRIDAY',
            'SATURDAY',
            'SUNDAY',
        ]
        present = set()
        for line in (text or '').splitlines():
            m = re.match(r'^\s*##\s*([A-Z]+DAY)\b', line.strip().upper())
            if m:
                present.add(m.group(1))
        return [d for d in required if d not in present]

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
        Build the AI prompt for plan generation.

        Args:
            workout_history: Formatted workout history
            trainer_workouts: Formatted trainer workouts
            preferences: Formatted user preferences

        Returns:
            Complete prompt string
        """
        # Extract athlete profile and rules from config
        athlete_config = self._format_athlete_config()

        fort_constraints_block = ""
        if fort_week_constraints:
            fort_constraints_block = f"""\nFORT WEEK CONSTRAINTS (from program preamble; treat as high priority):\n{fort_week_constraints}\n"""

        prompt = f"""You are an expert strength and conditioning coach creating a personalized weekly workout plan for {self.config['athlete']['name']}.

CRITICAL OUTPUT RULES:
- **NO RANGES**: Use single values only (e.g., "15 reps" not "12-15", "24 kg" not "22-26 kg")

{athlete_config}

{fort_constraints_block}

---

{workout_history}

---

{trainer_workouts}

---

{preferences}

---

EXERCISE SWAP RULES - APPLY THESE AUTOMATICALLY:
{self._load_exercise_swaps()}

CRITICAL INSTRUCTIONS FOR PLAN CREATION:

**READING FORT INSTRUCTIONS FOR SUPPLEMENTAL ADJUSTMENTS:**

Carefully analyze Fort workouts for intensity indicators that should inform supplemental programming:

- **Percentage targets** (e.g., "85% 1RM"): If Fort is heavy (>80% 1RM), reduce supplemental intensity to RPE 6-7
- **RPE cues** (e.g., "RPE 8-9", "work to near failure"): If Fort prescribes high RPE, keep supplemental moderate (RPE 6-7)
- **Volume spikes**: If Fort has unusually high set counts, reduce supplemental volume by 1-2 sets per exercise
- **Rep ranges**: If Fort moves to lower reps (1-5 strength phase), keep supplemental higher reps (8-15 hypertrophy)
- **Coach notes about fatigue**: If notes mention "tough week", "grinder sets", or "deload", reduce supplemental intensity
- **Exercise selection signals**: If Fort adds more accessories than usual, reduce supplemental exercise count

**Progressive Overload from Prior Week Logs:**

The workout history section contains prior week's logged performance. Use this data intelligently:

- **User logged MORE reps than prescribed**: Increase load by 2.5-5kg for next week
- **User logged exact reps with good form**: Maintain load or increase by 2.5kg (conservative progression)
- **User logged FEWER reps or noted "struggled"**: Maintain same load or reduce by 2.5kg if needed
- **Pay attention to RPE, Form, Energy notes**: If user noted "RPE 9" or "form breakdown", don't increase load
- **Look for patterns**: If user consistently hits top of rep range, they're ready for load progression
- **Recovery signals**: If Energy was "Fatigued" or notes mention poor sleep, be conservative with progression

**Non-Negotiable Swap Directives from User Logs:**

The workout history section may contain lines like "SWAP ...", "never do ...", "hate these", or explicit replacement prescriptions.

- Treat these as HARD CONSTRAINTS.
- If an exercise has a SWAP directive, do NOT carry it forward for progressive overload.
- Replace it with the requested alternative while preserving the intent (same muscle) and keep the user-prescribed sets/reps/load when provided.

**Integration Principle:** Fort workouts are priority #1. Supplemental work must support, not interfere with, Fort performance.

1. **MONDAY, WEDNESDAY, FRIDAY (Main Days - Fort Workouts):**
   - Use the trainer workouts provided above but REFORMAT them for consistent parsing
   - **IMPORTANT**: Apply all exercise swaps listed above BEFORE formatting
   - The trainer workout section headers may include a Fort workout title (e.g., "Monday (Gameday #4)")
     * You MUST carry that title into the day header format: `## MONDAY - FORT WORKOUT (Gameday #4)`
     * If no title is provided, omit the title and use a generic header (no invented titles)
   - Convert each exercise/drill into the standardized format shown below
   - Preserve ALL training content: sets, reps, weights, rest periods, coaching notes
   - For sections with multiple exercises (like PREP or MYO REP FINISHER), list each exercise individually
   - Label exercises sequentially: A1, A2, A3, B1, B2, etc.
   - For T.H.A.W./CIRCUIT conditioning work, if there are team/partner/solo options, ALWAYS use the solo variant

   **Required format for EVERY Fort exercise:**
   ```
   ### A1. [Exercise Name]
   - [Sets] x [Reps] @ [Weight] kg (single values only)
   - **Rest:** [Rest period]
   - **RPE:** [Target RPE]
   - **Form:** [Key form cues]
   - **Energy:** [Expected energy level]
   - **Adjustments:** [Any modifications]
   - **Notes:** [Coaching cues]
   ```

   **EXERCISE NAMING RULES:**
   1. Bench exercises: ALWAYS specify angle (e.g., "30° Incline DB Press")
   2. Cable exercises with two cables: Specify load per side
   3. Free weight carries: Use kettlebells (not dumbbells)

   **REST PERIOD RULES:**
   - **Fort Days (Mon/Wed/Fri)**: Follow trainer's prescribed rest periods. If not specified:
     * Main lifts (squats, deadlifts, presses): 3-5 minutes
     * Accessory compounds: 2-3 minutes
     * Isolation work: 60-90 seconds
   - **Supplemental Days (Tue/Thu/Sat)**:
     * Main movements (A, B blocks): 90-120 seconds
     * Isolation (C, D, E blocks): 60-90 seconds
     * Finishers/carries: 30-45 seconds

2. **TUESDAY, THURSDAY, SATURDAY (Supplemental Days):**
   - Use ### A1. [Exercise] format with bullet points
   - Focus on AESTHETICS: arms, medial delts, upper chest, back detail
   - MUST NOT compromise next main day's performance
   - **NO RANGES**: Single rep and load values only

   **INCLINE WALKING (MANDATORY):**
   - Warm-up: 10min @ 3.4 mph, 6% grade
   - Finisher: 15min @ 3.5 mph, 6% grade

   **SUPPLEMENTAL DAY INTERFERENCE CHECKS:**

   Before finalizing supplemental exercises, verify against Fort schedule to prevent interference:

   **Tuesday (post-Monday squat, pre-Wednesday press):**
   - ❌ Avoid: Heavy leg work (squats, lunges, heavy leg compounds), heavy pressing movements
   - ✅ Safe: Arms (biceps, triceps), shoulders (lateral/rear delts), upper chest, back detail work
   - ⚠️ Recovery concern: Don't fatigue grip or core heavily before Wednesday's pressing work

   **Thursday (post-Wednesday press, pre-Friday deadlift):**
   - ❌ Avoid: Heavy bicep/forearm work, heavy back pulling, exercises that tax grip strength
   - ✅ Safe: Legs (accessories, light work - not heavy squats), chest accessories, delts (all heads)
   - ⚠️ Recovery concern: Preserve grip strength for Friday deadlifts - no heavy curls or farmer walks

   **Saturday (post-Friday deadlift):**
   - ❌ Avoid: Heavy lower back loading, heavy leg compounds, heavy deadlift variations
   - ✅ Safe: Upper body focus - arms, chest, delts, light back accessories (no heavy rows)
   - ⚠️ Recovery concern: Allow CNS recovery from Friday's deadlift session

   **Additional Recovery Rules:**
   - If Fort day heavily loads shoulders, avoid heavy overhead work day before/after
   - Never train same muscle group heavy two days in a row
   - Cap total weekly bicep hard sets at 10-12 across rolling 4-day window
   - Monitor cumulative fatigue - if Fort week is brutal, dial back supplemental intensity

3. **SUNDAY:**
   - Active recovery or rest day
   - Light movement, stretching, or optional easy cardio
   - Sauna when appropriate

4. **DAILY STRUCTURE:**
   Every session must start with:
   - McGill Big-3 warm-up (bird-dog, side plank, curl-up)

5. **MANDATORY HARD RULES - YOU MUST FOLLOW THESE:**

   **Equipment & Exercise Selection:**
   - NO belt on pulls/deadlifts
   - Standing calf raises ONLY (NEVER seated calves)
   - NO split squats (any variant) - use alternatives from swap library

   **Biceps Programming (CRITICAL):**
   - NEVER same grip two days in a row
   - Rotate grips: supinated → neutral → pronated
   - Keep ~48 hours before another long-length stimulus (e.g., incline curls)
   - Cap biceps hard sets at 10-12 per rolling 4 days
   - Track grip rotation across the week

   **Triceps Programming:**
   - Vary attachments across Tue/Fri/Sat
   - NO single-arm D-handle on Saturday

   **Carries & Grip Work:**
   - Place carries on Tuesday only
   - Keep at RPE 6-7, shorter distances (to preserve Friday deadlift grip)

   **Lateral Raises:**
   - If Monday has lateral raises and Tuesday would conflict, use alternatives:
     * Reverse pec deck, cable Y-raise (low→high), or rear-delt face pulls

6. **PROGRESSION GUIDANCE:**
   - Barbell main lifts: If last top set ≤ RPE 9 (≥1 RIR), add 2.5-5 kg or 1-2 reps
   - Dumbbells: Move up one step after hitting top of rep range on ≥2 clean sets with RPE ≤8
   - Cable/Machine: When top of range is clean (RPE 7-8), add one plate next session
   - Round: barbell to 0.5 kg, DBs to nearest available step
   - **Use RPE tracking**: Target RPE 7-8 for supplemental work; if user logged RPE 9-10, reduce load
   - **Use Form tracking**: Only progress if prior week showed good form; form breakdown = maintain load
   - **Use Energy tracking**: If prior week showed "Fatigued", be conservative with progression

7. **1RM REFERENCES (for calculating percentages if needed):**
   - Back Squat: 129 kg
   - Bench Press: 94 kg
   - Deadlift: 168 kg

8. **FINISHERS:**
   - Include incline walking on supplemental days
   - THAW intensity must preserve next day performance (don't trash recovery)
   - Sauna after main days when appropriate

9. **SANITY CHECK BEFORE FINALIZING:**
   Before you output the plan, verify:
   - ✓ No same-grip biceps on consecutive days
   - ✓ Biceps hard sets ≤ 10-12 per rolling 4 days
   - ✓ Standing calf raises only (no seated)
   - ✓ Triceps attachments varied across Tue/Fri/Sat
   - ✓ No split squats anywhere
   - ✓ Carries on Tuesday at moderate load
   - ✓ THAW/finisher intensity won't compromise next day
   - ✓ Sauna included after main days

10. **OUTPUT FORMAT:**

Use American spelling throughout. Format as markdown with ## for day headers and ### for exercises:

```
# WEEKLY WORKOUT PLAN FOR SAMUEL
Generated: [current date]
Focus: Strength + Aesthetics (arms, medial delts, upper chest, back detail)

---

## MONDAY - FORT WORKOUT (Main Day)

**Warm-up:**
- McGill Big-3

### A1. [First PREP Exercise]
- [Sets] x [Reps/Time] @ [Load]
- **Rest:** [Rest period]
- **RPE:** [Target RPE]
- **Form:** [Key form cues]
- **Energy:** [Expected energy level]
- **Adjustments:** [Any modifications]
- **Notes:** [Coaching cues]

### A2. [Second PREP Exercise]
- [Sets] x [Reps/Time] @ [Load]
- **Rest:** [Rest period]
- **RPE:** [Target RPE]
- **Form:** [Key form cues]
- **Energy:** [Expected energy level]
- **Adjustments:** [Any modifications]
- **Notes:** [Coaching cues]

[Continue with all Fort exercises in ### A1., ### B1., etc. format]

---

## TUESDAY - AESTHETICS + ARMS

**Warm-up:**
- McGill Big-3

### A1. [Exercise Name]
- [Sets] x [Reps] @ [Load] kg
- **Rest:** [Rest period]
- **RPE:** [Target RPE]
- **Form:** [Key form cues, grip type for biceps]
- **Energy:** [Expected energy level]
- **Adjustments:** [Any modifications]
- **Notes:** [Additional coaching cues]

### A2. [Exercise Name]
- [Sets] x [Reps] @ [Load] kg
- **Rest:** [Rest period]
- **RPE:** [Target RPE]
- **Form:** [Key form cues]
- **Energy:** [Expected energy level]
- **Adjustments:** [Any modifications]
- **Notes:** [Coaching cues]

[Continue with all supplemental exercises in ### format]

**Finisher:**
- Incline walk: [duration/intensity]

**Post-workout:**
- Sauna optional

---

## WEDNESDAY - FORT WORKOUT (Main Day)

[Same standardized ### format as Monday]

---

## THURSDAY - AESTHETICS + BACK DETAIL

[Same standardized ### format as Tuesday]

---

## FRIDAY - FORT WORKOUT (Main Day)

[Same standardized ### format as Monday]

---

## SATURDAY - AESTHETICS + ARMS

[Same standardized ### format as Tuesday]

---

## SUNDAY - ACTIVE RECOVERY / REST

**Optional activities:**
- Light movement, stretching, or easy cardio
- Sauna

---

## WEEKLY PROGRAMMING NOTES:
- [Bicep grip rotation summary across the week]
- [Progressive overload guidance for supplemental exercises]
- [Recovery and readiness notes]
- [Any specific form cues or technique reminders]
- [Sanity check confirmation]

```

**CRITICAL**: Every single exercise (Fort and supplemental) MUST use the ### A1. format with bullet points for sets/reps/load/rest/notes. This ensures consistent parsing to Google Sheets.

Generate the complete weekly workout plan now, following ALL rules above:
"""

        return prompt

    def _format_athlete_config(self):
        """Format the athlete configuration section for the prompt."""
        config_text = f"""
ATHLETE PROFILE:
• Name: {self.config['athlete']['name']}
• Units: {self.config['athlete']['units']}
• Spelling: {self.config['athlete']['spelling']}

PRIMARY GOALS:
• {self.config['goals']['primary']}

FOCUS AREAS:
• {', '.join(self.config['goals']['focus_areas'])}

WEEKLY STRUCTURE:
• Main Days: {', '.join(self.config['weekly_structure']['main_days'])}
  ({self.config['weekly_structure']['main_days_note']})
• Supplemental Days: {', '.join(self.config['weekly_structure']['supplemental_days'])}
  ({self.config['weekly_structure']['supplemental_days_note']})
• Daily Warm-up: {self.config['weekly_structure']['daily_warmup']}

HARD RULES (NON-NEGOTIABLE):
"""
        for rule in self.config['hard_rules']['equipment']:
            config_text += f"• {rule}\n"

        config_text += "\nBICEPS RULES:\n"
        for rule in self.config['hard_rules']['biceps']:
            config_text += f"• {rule}\n"

        config_text += f"\nSPELLING: {self.config['hard_rules']['spelling']}\n"

        config_text += """
SWAP LIBRARY (if needed):
"""
        for exercise, alternatives in self.config['swap_library'].items():
            if isinstance(alternatives, list):
                config_text += f"• {exercise.replace('_', ' ').title()}: {', '.join(alternatives)}\n"
            else:
                config_text += f"• {exercise.replace('_', ' ').title()}: {alternatives.get('note', '')}\n"

        return config_text

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
