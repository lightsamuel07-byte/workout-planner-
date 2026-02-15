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


if __name__ == "__main__":
    unittest.main()
