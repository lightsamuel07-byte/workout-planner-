import unittest

from src.plan_validator import validate_plan


class PlanValidatorTests(unittest.TestCase):
    def test_detects_odd_dumbbell_load_violation(self):
        plan = """## TUESDAY
### B1. DB Lateral Raise
- 4 x 12 @ 7 kg
- **Rest:** 60 seconds
- **Notes:** Strict form.
"""
        result = validate_plan(plan, progression_directives=[])
        codes = {v["code"] for v in result["violations"]}
        self.assertIn("odd_db_load", codes)

    def test_detects_hold_lock_violation(self):
        plan = """## THURSDAY
### D1. Hammer Curl (Neutral Grip)
- 3 x 10 @ 16 kg
- **Rest:** 60 seconds
- **Notes:** Hold until form improves.
"""
        directives = [
            {
                "day_name": "thursday",
                "exercise_name": "Hammer Curl (Neutral Grip)",
                "hold_lock": True,
                "target_reps": 12,
                "target_load": 16.0,
            }
        ]
        result = validate_plan(plan, progression_directives=directives)
        codes = {v["code"] for v in result["violations"]}
        self.assertIn("hold_lock_violation", codes)

    def test_detects_odd_db_squat_load_violation(self):
        plan = """## WEDNESDAY
### E1. Low-Hold DB Goblet Squat
- 3 x 8 @ 29 kg
- **Rest:** 90 seconds
- **Notes:** Control tempo.
"""
        result = validate_plan(plan, progression_directives=[])
        codes = {v["code"] for v in result["violations"]}
        self.assertIn("odd_db_load", codes)

    def test_does_not_flag_biceps_rotation_when_notes_mention_other_days(self):
        plan = """## TUESDAY
### D1. Incline DB Curl (Supinated)
- 3 x 12 @ 14 kg
- **Rest:** 60 seconds
- **Notes:** Supinated grip. Long-length stimulus.
## THURSDAY
### D1. Cable Curl (Straight Bar, Pronated Grip)
- 3 x 10 @ 27 kg
- **Rest:** 60 seconds
- **Notes:** Pronated grip to avoid repeat (Tue supinated -> Thu pronated -> Sat neutral).
## SATURDAY
### D1. Hammer Curl (Neutral Grip)
- 3 x 15 @ 14 kg
- **Rest:** 60 seconds
- **Notes:** Neutral grip to complete rotation (Tue supinated -> Thu pronated -> Sat neutral).
"""
        result = validate_plan(plan, progression_directives=[])
        codes = {v["code"] for v in result["violations"]}
        self.assertNotIn("biceps_grip_repeat", codes)

    def test_detects_underfilled_supplemental_day(self):
        plan = """## TUESDAY
### D1. Incline DB Curl (Supinated)
- 3 x 12 @ 14 kg
- **Rest:** 60 seconds
- **Notes:** Supinated grip.
### D2. Rope Pressdown
- 3 x 12 @ 22 kg
- **Rest:** 60 seconds
- **Notes:** Triceps.
### D3. Face Pull
- 3 x 15 @ 18 kg
- **Rest:** 60 seconds
- **Notes:** Upper back.
## THURSDAY
### D1. Cable Curl (Pronated Grip)
- 3 x 10 @ 20 kg
- **Rest:** 60 seconds
- **Notes:** Pronated grip.
### D2. Floor Press
- 3 x 10 @ 24 kg
- **Rest:** 90 seconds
- **Notes:** Control.
### D3. Rear Delt Raise
- 3 x 15 @ 8 kg
- **Rest:** 60 seconds
- **Notes:** Tempo.
## SATURDAY
### D1. Triceps Pushdown (V-Bar)
- 3 x 12 @ 22 kg
- **Rest:** 60 seconds
- **Notes:** Single exercise day.
"""
        result = validate_plan(plan, progression_directives=[])
        codes = {v["code"] for v in result["violations"]}
        self.assertIn("supplemental_day_underfilled", codes)

    def test_detects_fort_header_as_exercise_noise(self):
        plan = """## MONDAY
### F1. PREPARE TO ENGAGE
- 1 x 60 @ 0 kg
- **Rest:** None
- **Notes:** Header leaked into exercise list.
### F2. Meters
- 1 x 60 @ 0 kg
- **Rest:** None
- **Notes:** Table label leaked into exercise list.
"""
        result = validate_plan(plan, progression_directives=[])
        codes = {v["code"] for v in result["violations"]}
        self.assertIn("fort_header_as_exercise", codes)


if __name__ == "__main__":
    unittest.main()
