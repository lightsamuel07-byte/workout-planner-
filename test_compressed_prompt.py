#!/usr/bin/env python3
"""
Manual script to compare a compressed prompt variant against the default prompt.
"""

import os
import sys

import yaml
from dotenv import load_dotenv

sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from plan_generator import PlanGenerator


class CompressedPlanGenerator(PlanGenerator):
    def _build_prompt(
        self,
        workout_history,
        trainer_workouts,
        preferences,
        fort_week_constraints=None,
        db_context=None,
        progression_directives_block=None,
    ):
        athlete_config = self._format_athlete_config_compressed()
        fort_constraints_block = ""
        if fort_week_constraints:
            fort_constraints_block = f"\nFORT WEEK CONSTRAINTS:\n{fort_week_constraints}\n"

        return f"""You are an expert strength and conditioning coach creating a personalized weekly workout plan for {self.config['athlete']['name']}.

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
- Fort workouts (Mon/Wed/Fri) are priority #1 - reformat to ### A1. format but preserve content
- Supplemental days (Tue/Thu/Sat) support Fort work - focus: arms, medial delts, upper chest, back detail
- Progressive overload: +2.5-5kg if user exceeded reps, maintain if struggled, +2.5kg if exact
- SWAP directives from logs are HARD constraints - replace as requested, do not progress

MANDATORY HARD RULES:
- Equipment: No belt on pulls, standing calves only, no split squats
- Dumbbells: even-number loads only (main barbell lifts excluded)
- Biceps: Rotate grips (supinated -> neutral -> pronated), never repeat on adjacent supplemental days
- Triceps: Vary attachments Tue/Fri/Sat, no single-arm D-handle Sat
- Carries: Tuesday only

EXERCISE FORMAT (ALL EXERCISES):
### A1. [Exercise Name]
- [Sets] x [Reps] @ [Load] kg
- **Rest:** [period]
- **Notes:** [coaching]

OUTPUT: Use ## day headers and the exact exercise format above.
Generate complete weekly plan following ALL rules above."""


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
90/90 HIP SWITCH - 01:00.00
CLUSTER WARM UP
BACK SQUAT
5 Sets
1. 10 reps @ 15.5 kg (12%)
"""

    formatted_workouts = f"""
TRAINER WORKOUTS FROM TRAIN HEROIC:

=== Monday ===
{fort_monday}

=== Wednesday ===
Sample Wednesday Bench workout

=== Friday ===
Sample Friday Deadlift workout
"""

    preferences = """
USER PREFERENCES:
- Goal: maximize aesthetics without interfering with Mon/Wed/Fri Fort program
- Supplemental Days: Tuesday, Thursday, Saturday
"""
    workout_history = "No prior workout history available (new program)."

    print("=" * 80)
    print("TESTING COMPRESSED PROMPT")
    print("=" * 80)

    print("\n1) Running default prompt...")
    default_gen = PlanGenerator(api_key=api_key, config=config)
    default_plan, _default_expl, _default_validation = default_gen.generate_plan(
        workout_history, formatted_workouts, preferences
    )
    default_exercises = default_plan.count('### ') if default_plan else 0
    print(f"Default plan exercises: {default_exercises}")

    print("\n2) Running compressed prompt variant...")
    compressed_gen = CompressedPlanGenerator(api_key=api_key, config=config)
    compressed_plan, _compressed_expl, _compressed_validation = compressed_gen.generate_plan(
        workout_history, formatted_workouts, preferences
    )
    compressed_exercises = compressed_plan.count('### ') if compressed_plan else 0
    print(f"Compressed plan exercises: {compressed_exercises}")

    if default_plan and compressed_plan:
        print("\nBoth prompts generated successfully.")
        return 0

    print("\nOne or both prompt variants failed.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
