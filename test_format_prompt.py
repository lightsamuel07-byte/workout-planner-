#!/usr/bin/env python3
"""
Manual script to verify prompt formatting behavior.
"""

import os
import sys

import yaml
from dotenv import load_dotenv

sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from plan_generator import PlanGenerator


def main():
    with open('config.yaml', 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)

    load_dotenv()
    api_key_env = config['claude']['api_key_env']
    api_key = os.getenv(api_key_env)
    if not api_key:
        print(f"ERROR: {api_key_env} not found in environment!")
        return 1

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
- Goal: maximize aesthetics without interfering with Mon/Wed/Fri Fort program
- Training Approach: progressive overload
- Supplemental Days: Tuesday, Thursday, Saturday
- Rest Day: Sunday
"""

    workout_history = "No prior workout history available (new program)."

    print("=" * 80)
    print("TESTING NEW PROMPT FORMAT")
    print("=" * 80)
    print("\nGenerating plan with updated prompt formatting...\n")

    plan_gen = PlanGenerator(api_key=api_key, config=config)
    plan, _explanation, _validation_summary = plan_gen.generate_plan(
        workout_history, formatted_workouts, preferences
    )

    if not plan:
        print("\nERROR: Failed to generate plan")
        return 1

    plan_path, explanation_path = plan_gen.save_plan(plan)

    print("\n" + "=" * 80)
    print("GENERATED PLAN - First 3000 characters:")
    print("=" * 80)
    print(plan[:3000])
    print("\n[...truncated...]")

    print("\n" + "=" * 80)
    print("FORMAT VALIDATION:")
    print("=" * 80)

    lines = plan.split('\n')
    exercise_count = 0
    exercises = []
    for line in lines:
        if line.startswith('### ') and '. ' in line:
            exercise_line = line.replace('### ', '').strip()
            parts = exercise_line.split('. ', 1)
            block_label = parts[0].strip()
            if len(block_label) <= 3 and block_label[0].isalpha():
                exercise_count += 1
                exercises.append(line.strip())

    print(f"\nFound {exercise_count} exercises in ### A1. format")
    print("\nFirst 10 exercises:")
    for i, ex in enumerate(exercises[:10], 1):
        print(f"  {i}. {ex}")

    if exercise_count >= 30:
        print(f"\nSUCCESS: Found {exercise_count} exercises")
    else:
        print(f"\nWARNING: Only found {exercise_count} exercises (expected 30+)")

    print(f"\nSaved plan to: {plan_path}")
    if explanation_path:
        print(f"Saved explanation to: {explanation_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
