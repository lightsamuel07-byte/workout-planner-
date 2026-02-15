import unittest

from pages.generate_plan import should_start_plan_generation


class GeneratePlanButtonFlowTest(unittest.TestCase):
    def test_starts_when_clicked_and_not_in_progress(self):
        self.assertTrue(should_start_plan_generation(True, False))

    def test_does_not_start_when_already_in_progress(self):
        self.assertFalse(should_start_plan_generation(True, True))

    def test_does_not_start_without_click(self):
        self.assertFalse(should_start_plan_generation(False, False))

    def test_does_not_start_with_missing_inputs(self):
        self.assertFalse(should_start_plan_generation(True, False, all_workouts_filled=False))


if __name__ == "__main__":
    unittest.main()
