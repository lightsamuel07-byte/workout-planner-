"""
AI-powered workout plan generation using Claude API.
"""

import anthropic
import os
import yaml
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

    def generate_plan(self, workout_history, trainer_workouts, preferences):
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
        prompt = self._build_prompt(workout_history, trainer_workouts, preferences)

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
            print("✓ Workout plan generated successfully!\n")
            return plan

        except Exception as e:
            print(f"Error generating plan: {e}")
            return None

    def _build_prompt(self, workout_history, trainer_workouts, preferences):
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

        prompt = f"""You are an expert strength and conditioning coach creating a personalized weekly workout plan for {self.config['athlete']['name']}.

{athlete_config}

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
   ### A1. [Exercise Name] (specify bench angle if applicable, e.g., "30° Incline DB Press")
   - [Sets] x [Reps] @ [Weight] kg (or time format like 1:00 for timed drills; for two-cable exercises, specify "per side")
   - **Rest:** [Rest period from trainer, or intelligent default]
   - **RPE:** [Target Rate of Perceived Exertion, 1-10 scale]
   - **Form:** [Key form cues and technique focus]
   - **Energy:** [Expected energy level: Fresh/Moderate/Fatigued]
   - **Adjustments:** [Any modifications from standard form]
   - **Notes:** [Additional coaching cues, tempo, technique notes, percentages]
   ```

   **EXERCISE NAMING RULES (CRITICAL):**
   1. **Bench exercises**: ALWAYS specify angle
      - ✅ Correct: "30° Incline DB Press", "Flat Bench Press", "15° Decline DB Fly"
      - ❌ Wrong: "Incline Press" (missing degree), "DB Bench" (missing angle)

   2. **Cable exercises with two cables**: Specify load per side
      - ✅ Correct: "15 kg per side" for High-to-Low Cable Fly
      - ✅ Single cable: Just specify total load (e.g., "20 kg")

   3. **Machine exercises**: Specify grip/attachment
      - ✅ Examples: "Lat Pulldown (Wide Grip)", "Cable Row (V-Handle)"

   4. **Free weight carries**: Use kettlebells (not dumbbells)
      - ✅ Correct: "Kettlebell Farmer Carry", "KB Suitcase Carry"
      - ❌ Wrong: "DB Farmer Carry", "Dumbbell Carry"

   **Example - Converting a PREP section:**
   Original from user:
   ```
   PREP
   1 Set
   90/90 HIP SWITCH - 01:00.00 (Rotate side to side)
   FIGURE 4 GLUTE ACTIVATION - 01:00.00 (30 seconds per side)
   ```

   Your formatted output:
   ```
   ### A1. 90/90 Hip Switch
   - 1 x 1:00
   - **Rest:** 0s (flow into next drill)
   - **Notes:** Rotate side to side without hands (ninja level)

   ### A2. Figure 4 Glute Activation
   - 1 x 1:00
   - **Rest:** 0s (flow into next drill)
   - **Notes:** 30 seconds per side
   ```

   **Example - Converting CLUSTER SET SINGLES:**
   Original from user:
   ```
   CLUSTER SET SINGLES - BACK SQUAT
   5 Sets x 1 rep @ 96.5 kg (75%)
   Un-rack for new rep every 45 seconds
   ```

   Your formatted output:
   ```
   ### C1. Back Squat (Cluster Singles)
   - 5 x 1 @ 96.5 kg
   - **Rest:** 45s between reps, 3min after set 5
   - **Notes:** Un-rack for new rep every 45s; max bar speed and performance intent; 75% training max
   ```

   **Example - Converting MYO REP FINISHER:**
   Original from user:
   ```
   MYO REP FINISHER
   3 Sets
   30° INCLINE DB BENCH PRESS - 8 reps
   DB RDL (GLUTE OPTIMIZED) - 12 reps
   ```

   Your formatted output:
   ```
   ### E1. 30° Incline DB Bench Press
   - 3 x 8 @ 24-26 kg
   - **Rest:** 60s
   - **Notes:** Upper chest focus; controlled eccentric; last set = myo-rep

   ### E2. DB RDL (Glute Optimized)
   - 3 x 12 @ 28-32 kg
   - **Rest:** 60s
   - **Notes:** Glute emphasis; last set = myo-rep (1 RIR, rest 10-15s, 3-4 more reps x 3 rounds)
   ```

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
   Design workouts using the SAME EXACT format as Fort workouts above:
   - Use the ### A1. [Exercise] format with bullet points
   - Focus on AESTHETICS + accessory work
   - Target the focus areas: arms, medial delts, upper chest, back detail
   - MUST NOT compromise the next main day's performance
   - Keep intensity moderate - these are supplemental, not primary training days
   - Focus on progressive overload from prior week's log (if continuing same program)
   - OR design fresh supplemental workouts (if new Fort program)

   **INCLINE WALKING (MANDATORY for all supplemental days):**
   - **Warm-up**: 10 minutes incline walk before lifting (baseline: 3.4 mph @ 6% incline, but adjust for optimal aesthetics benefit and readiness)
   - **Finisher**: 15 minutes incline walk after lifting (baseline: 3.5 mph @ 6% incline, but optimize for fat loss and recovery without compromising next day)
   - Consider: Samuel's conditioning level, proximity to next Fort workout, and aerobic capacity
   - Format incline walks as exercises in the plan using the ### format

   **Use the EXACT SAME format structure with ALL fields:**
   ```
   ### A1. Incline Walk (Warm-up)
   - 1 x 10:00 @ 3.4 mph, 6% grade
   - **Rest:** 2-3min before first exercise
   - **RPE:** 3-4
   - **Form:** Upright posture, glutes engaged
   - **Energy:** Fresh
   - **Adjustments:** Adjust speed/grade based on readiness
   - **Notes:** Increase blood flow, activate glutes and hamstrings

   ### A2. Cable Lateral Raise
   - 3 x 12-15 @ 20 kg
   - **Rest:** 90s
   - **RPE:** 7-8
   - **Form:** Constant tension through range; wrist height
   - **Energy:** Fresh to moderate
   - **Adjustments:** None
   - **Notes:** Medial delt focus; avoid momentum

   [... other exercises ...]

   ### F1. Incline Walk (Finisher)
   - 1 x 15:00 @ 3.5 mph, 6% grade
   - **Rest:** N/A (end of session)
   - **RPE:** 4-5
   - **Form:** Maintain upright posture throughout
   - **Energy:** Fatigued but controlled
   - **Adjustments:** None
   - **Notes:** Steady pace for fat oxidation; should not compromise next day's performance
   ```

   **CRITICAL: SUPPLEMENTAL DAY INTERFERENCE CHECKS**

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

    def save_plan(self, plan, output_folder="output", format="markdown"):
        """
        Save the generated plan to a file.

        Args:
            plan: The generated plan text
            output_folder: Folder to save the plan
            format: File format (markdown, text, json)

        Returns:
            Path to saved file
        """
        if not plan:
            print("No plan to save.")
            return None

        # Create output folder if it doesn't exist
        os.makedirs(output_folder, exist_ok=True)

        # Generate filename with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        extension = "md" if format == "markdown" else "txt"
        filename = f"workout_plan_{timestamp}.{extension}"
        filepath = os.path.join(output_folder, filename)

        # Save the plan
        with open(filepath, 'w') as f:
            f.write(plan)

        print(f"✓ Plan saved to: {filepath}")
        return filepath
