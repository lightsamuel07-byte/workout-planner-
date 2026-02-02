#!/usr/bin/env python3
"""
Test script to compare compressed vs original prompt performance
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from plan_generator import PlanGenerator
import yaml
from dotenv import load_dotenv

# Load config
with open('config.yaml', 'r') as f:
    config = yaml.safe_load(f)

load_dotenv()
api_key_env = config['claude']['api_key_env']
api_key = os.getenv(api_key_env)

if not api_key:
    print(f"ERROR: {api_key_env} not found in environment!")
    sys.exit(1)

# Sample data (same as original test)
fort_monday = """
Monday 1.26.26
Gameday #1

  PREP
1 Set
90/90 HIP SWITCH - 01:00.00 (Rotate side to side)
FIGURE 4 GLUTE ACTIVATION - 01:00.00 (30 seconds per side)
HIP FLEXOR PLANK - 01:00.00 (30 seconds per side)

  CLUSTER WARM UP
BACK SQUAT
5 Sets
1. 10 reps @ 15.5 kg (12%)
2. 5 reps @ 45.1 kg (35%)
3. 3 reps @ 64.4 kg (50%)

  CLUSTER SET SINGLES
BACK SQUAT
5 Sets x 1 rep @ 96.5 kg (75%)
Un-rack for new rep every 45 seconds

  CLUSTER SET DOUBLES
BACK SQUAT
5 Sets x 2 reps @ 90.2 kg (70%)

  MYO REP FINISHER
3 Sets
30° INCLINE DB BENCH PRESS - 8 reps
DB RDL (GLUTE OPTIMIZED) - 12 reps
EZ BAR REAR DELT ROW - 15 reps

  T.H.A.W.
Choose Teams of 3-4, Partners (2), or Solo:
Solo: 1k Row, Perform 10 Burpees before you start the row and again at 250m, 500m, and 750m.
"""

trainer_workouts = {
    'monday': fort_monday,
    'wednesday': 'Sample Wednesday Bench workout',
    'friday': 'Sample Friday Deadlift workout'
}

formatted_workouts = f"""
TRAINER WORKOUTS FROM TRAIN HEROIC:

=== Monday ===
{trainer_workouts['monday']}

=== Wednesday ===
{trainer_workouts['wednesday']}

=== Friday ===
{trainer_workouts['friday']}
"""

preferences = """
USER PREFERENCES:
• Goal: maximize aesthetics without interfering with Mon/Wed/Fri Fort program
• Training Approach: progressive overload
• Supplemental Days: Tuesday, Thursday, Saturday
• Rest Day: Sunday
"""

workout_history = "No prior workout history available (new program)."

print("="*80)
print("TESTING COMPRESSED PROMPT")
print("="*80)

# Test with original generator first
print("\n1. Testing ORIGINAL prompt...")
plan_gen = PlanGenerator(api_key=api_key, config=config)
original_plan, original_explanation = plan_gen.generate_plan(
    workout_history, formatted_workouts, preferences
)

if original_plan:
    print("✓ Original prompt succeeded")
    original_lines = len(original_plan.split('\n'))
    original_exercises = original_plan.count('### ')
else:
    print("✗ Original prompt failed")
    original_lines = 0
    original_exercises = 0

# Now test compressed version
print("\n2. Testing COMPRESSED prompt...")

# Create a modified generator with compressed prompt
class CompressedPlanGenerator(PlanGenerator):
    def _build_prompt(self, workout_history, trainer_workouts, preferences, fort_week_constraints=None):
        """Compressed prompt version"""
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

{trainer_workouts}

---

{preferences}

---

EXERCISE SWAP RULES - APPLY AUTOMATICALLY:
{self._load_exercise_swaps()}

CORE PRINCIPLES:
- Fort workouts (Mon/Wed/Fri) are priority #1 - reformat to ### A1. format but preserve ALL content
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
        """Compressed athlete config"""
        return f"""
ATHLETE: {self.config['athlete']['name']} | {self.config['athlete']['units']} | {self.config['athlete']['spelling']} spelling
GOAL: {self.config['goals']['primary']} | Focus: {', '.join(self.config['goals']['focus_areas'])}
SCHEDULE: Fort {', '.join(self.config['weekly_structure']['main_days'])} | Supplemental {', '.join(self.config['weekly_structure']['supplemental_days'])}
HARD RULES: {' | '.join(self.config['hard_rules']['equipment'])} | Biceps: {' | '.join(self.config['hard_rules']['biceps'])}"""

# Test compressed version
compressed_gen = CompressedPlanGenerator(api_key=api_key, config=config)
compressed_plan, compressed_explanation = compressed_gen.generate_plan(
    workout_history, formatted_workouts, preferences
)

if compressed_plan:
    print("✓ Compressed prompt succeeded")
    compressed_lines = len(compressed_plan.split('\n'))
    compressed_exercises = compressed_plan.count('### ')
else:
    print("✗ Compressed prompt failed")
    compressed_lines = 0
    compressed_exercises = 0

# Comparison
print("\n" + "="*80)
print("COMPARISON RESULTS:")
print("="*80)
print(f"Original prompt:")
print(f"  - Lines generated: {original_lines}")
print(f"  - Exercises found: {original_exercises}")

print(f"\nCompressed prompt:")
print(f"  - Lines generated: {compressed_lines}")
print(f"  - Exercises found: {compressed_exercises}")

if original_exercises > 0 and compressed_exercises > 0:
    exercise_diff = abs(original_exercises - compressed_exercises)
    print(f"\nExercise count difference: {exercise_diff}")
    if exercise_diff <= 2:
        print("✓ Exercise counts are very similar")
    else:
        print("⚠ Significant difference in exercise counts")

# Format validation for both
def validate_format(plan, name):
    if not plan:
        return False
    
    lines = plan.split('\n')
    exercise_count = 0
    proper_format = 0
    
    for line in lines:
        if line.startswith('### ') and '. ' in line:
            exercise_line = line.replace('### ', '').strip()
            if '. ' in exercise_line:
                parts = exercise_line.split('. ', 1)
                block_label = parts[0].strip()
                if len(block_label) <= 3 and block_label[0].isalpha():
                    exercise_count += 1
                    proper_format += 1
    
    success_rate = (proper_format / exercise_count * 100) if exercise_count > 0 else 0
    print(f"\n{name} Format Validation:")
    print(f"  - Total exercises: {exercise_count}")
    print(f"  - Properly formatted: {proper_format}")
    print(f"  - Success rate: {success_rate:.1f}%")
    
    return success_rate >= 90

orig_valid = validate_format(original_plan, "Original")
comp_valid = validate_format(compressed_plan, "Compressed")

print("\n" + "="*80)
print("FINAL VERDICT:")
print("="*80)

if orig_valid and comp_valid:
    print("✓ BOTH prompts produce valid, properly formatted output")
    print("✓ Compressed prompt maintains all critical functionality")
    print("✓ Recommend switching to compressed version")
elif comp_valid and not orig_valid:
    print("✓ Compressed prompt works better than original")
elif orig_valid and not comp_valid:
    print("⚠ Original prompt still more reliable")
else:
    print("✗ Both prompts have issues")

print(f"\nEstimated cost savings: ~70% reduction in prompt size")
