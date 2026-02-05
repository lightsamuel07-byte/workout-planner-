import unittest

from pages.workout_logger import build_log_entry, parse_existing_log_fields


class WorkoutLoggerFieldParsingTests(unittest.TestCase):
    def test_parse_empty_log(self):
        self.assertEqual(parse_existing_log_fields(""), ("", "", ""))

    def test_parse_performance_only(self):
        performance, rpe, notes = parse_existing_log_fields("12,12,10 @ 50kg")
        self.assertEqual(performance, "12,12,10 @ 50kg")
        self.assertEqual(rpe, "")
        self.assertEqual(notes, "")

    def test_parse_performance_rpe_notes(self):
        text = "10,10,8 @ 40kg | RPE 8.5 | Notes: felt strong"
        performance, rpe, notes = parse_existing_log_fields(text)
        self.assertEqual(performance, "10,10,8 @ 40kg")
        self.assertEqual(rpe, "8.5")
        self.assertEqual(notes, "felt strong")

    def test_parse_ignores_invalid_rpe_range(self):
        performance, rpe, notes = parse_existing_log_fields("10 reps | RPE 12")
        self.assertEqual(performance, "10 reps | RPE 12")
        self.assertEqual(rpe, "")
        self.assertEqual(notes, "")

    def test_build_log_entry_full(self):
        result = build_log_entry("10,10,8 @ 40kg", "8.5", "felt strong")
        self.assertEqual(result, "10,10,8 @ 40kg | RPE 8.5 | Notes: felt strong")

    def test_build_log_entry_trims_and_omits_empty(self):
        result = build_log_entry("  Done ", " ", "  ")
        self.assertEqual(result, "Done")


if __name__ == "__main__":
    unittest.main()
