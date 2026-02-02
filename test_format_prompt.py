#!/usr/bin/env python3
"""
Test script to verify the new prompt generates consistent formatting
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from plan_generator import PlanGenerator
import yaml

# Load config
with open('config.yaml', 'r') as f:
    config = yaml.safe_load(f)

# Load API key
from dotenv import load_dotenv
load_dotenv()

# Get API key from config
api_key_env = config['claude']['api_key_env']
api_key = os.getenv(api_key_env)

if not api_key:
    print(f"ERROR: {api_key_env} not found in environment!")
    sys.exit(1)

# Sample Fort workout (Monday from user's example)
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

# Mock trainer workouts
trainer_workouts = {
    'monday': fort_monday,
    'wednesday': 'Sample Wednesday Bench workout',
    'friday': 'Sample Friday Deadlift workout'
}

# Format for AI
formatted_workouts = f"""
TRAINER WORKOUTS FROM TRAIN HEROIC:

=== Monday ===
{trainer_workouts['monday']}

=== Wednesday ===
{trainer_workouts['wednesday']}

=== Friday ===
{trainer_workouts['friday']}
"""

# Mock preferences
preferences = """
USER PREFERENCES:
• Goal: maximize aesthetics without interfering with Mon/Wed/Fri Fort program
• Training Approach: progressive overload
• Supplemental Days: Tuesday, Thursday, Saturday
• Rest Day: Sunday
"""

# Mock workout history
workout_history = "No prior workout history available (new program)."

print("="*80)
print("TESTING NEW PROMPT FORMAT")
print("="*80)
print("\nGenerating plan with updated prompt that standardizes Fort workout format...")
print("This will call the Anthropic API - checking for consistent ### A1. formatting\n")

plan_gen = PlanGenerator(api_key=api_key, config=config)
plan, _explanation = plan_gen.generate_plan(workout_history, formatted_workouts, preferences)

if plan:
    # Save to output for inspection
    output_file = plan_gen.save_plan(plan)

    print("\n" + "="*80)
    print("GENERATED PLAN - First 3000 characters:")
    print("="*80)
    print(plan[:3000])
    print("\n[...truncated...]")

    # Check for consistent formatting
    print("\n" + "="*80)
    print("FORMAT VALIDATION:")
    print("="*80)

    lines = plan.split('\n')
    exercise_count = 0
    exercises = []

    for line in lines:
        if line.startswith('### ') and '. ' in line:
            exercise_line = line.replace('### ', '').strip()
            if '. ' in exercise_line:
                parts = exercise_line.split('. ', 1)
                block_label = parts[0].strip()
                if len(block_label) <= 3 and block_label[0].isalpha():
                    exercise_count += 1
                    exercises.append(line.strip())

    print(f"\n✓ Found {exercise_count} exercises in ### A1. format")
    print(f"\nFirst 10 exercises:")
    for i, ex in enumerate(exercises[:10], 1):
        print(f"  {i}. {ex}")

    if exercise_count >= 30:
        print(f"\n✓ SUCCESS: Found {exercise_count} exercises - format appears consistent!")
    else:
        print(f"\n⚠ WARNING: Only found {exercise_count} exercises - expected 30+")
        print("Check if Fort workouts were properly reformatted")

    print(f"\n✓ Full plan saved to: {output_file}")
else:
    print("\n✗ ERROR: Failed to generate plan")
