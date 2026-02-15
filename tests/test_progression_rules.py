import unittest

from src.progression_rules import (
    apply_locked_directives_to_plan,
    build_progression_directives,
)


class ProgressionRulesTests(unittest.TestCase):
    def test_build_directives_marks_keep_signal_as_hold_lock(self):
        prior_supplemental = {
            "Tuesday": [
                {
                    "exercise": "Reverse Pec Deck",
                    "reps": "18",
                    "load": "42.5",
                    "log": "Done, keep this weight and reps next week",
                }
            ],
            "Thursday": [],
            "Saturday": [],
        }

        directives = build_progression_directives(prior_supplemental)
        self.assertEqual(len(directives), 1)
        directive = directives[0]
        self.assertTrue(directive["hold_lock"])
        self.assertEqual(directive["target_reps"], 18)
        self.assertEqual(directive["target_load"], 42.5)

    def test_apply_locked_directive_updates_prescription_line(self):
        plan = """## TUESDAY
### B2. Reverse Pec Deck
- 4 x 18 @ 42 kg
- **Rest:** 60 seconds
- **Notes:** Hold here.
"""
        directives = [
            {
                "day_name": "tuesday",
                "exercise_name": "Reverse Pec Deck",
                "hold_lock": True,
                "target_reps": 18,
                "target_load": 42.5,
            }
        ]

        updated, applied = apply_locked_directives_to_plan(plan, directives)
        self.assertEqual(applied, 1)
        self.assertIn("- 4 x 18 @ 42.5 kg", updated)


if __name__ == "__main__":
    unittest.main()
