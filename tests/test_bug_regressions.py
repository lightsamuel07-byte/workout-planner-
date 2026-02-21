import os
import tempfile
import unittest
from unittest.mock import MagicMock

from pages.view_plans import parse_plan_content
from src.analytics import WorkoutAnalytics
from src.sheets_reader import SheetsReader


class SheetsReaderWeeklyPlanFilterTests(unittest.TestCase):
    def _build_reader_with_sheet_titles(self, titles):
        reader = SheetsReader(
            credentials_file="credentials.json",
            spreadsheet_id="spreadsheet-id",
            sheet_name="Sheet1",
        )
        reader.service = MagicMock()
        reader.service.spreadsheets().get().execute.return_value = {
            "sheets": [{"properties": {"title": title}} for title in titles]
        }
        return reader

    def test_get_all_weekly_plan_sheets_excludes_archived_tabs(self):
        reader = self._build_reader_with_sheet_titles(
            [
                "Random Tab",
                "(Weekly Plan) 2/7/2026",
                "Weekly Plan (2/14/2026)",
                "Weekly Plan (2/21/2026) [archived 2026-02-21 15:00:00]",
            ]
        )

        sheets = reader.get_all_weekly_plan_sheets()

        self.assertEqual(
            sheets,
            ["(Weekly Plan) 2/7/2026", "Weekly Plan (2/14/2026)"],
        )

    def test_find_most_recent_weekly_plan_ignores_archived_tabs(self):
        reader = self._build_reader_with_sheet_titles(
            [
                "Weekly Plan (2/14/2026)",
                "Weekly Plan (2/21/2026) [archived 2026-02-21 15:00:00]",
            ]
        )

        most_recent = reader.find_most_recent_weekly_plan()

        self.assertEqual(most_recent, "Weekly Plan (2/14/2026)")


class AnalyticsRegressionTests(unittest.TestCase):
    def test_main_lift_progression_uses_workout_order_not_string_sort(self):
        analytics = WorkoutAnalytics(sheets_reader=None)
        analytics.historical_data = [
            {
                "sheet_name": "Weekly Plan (2/10/2026)",
                "date": "Monday 2/10/2026",
                "exercises": [{"exercise": "Back Squat", "load": "100 kg"}],
            },
            {
                "sheet_name": "Weekly Plan (2/10/2026)",
                "date": "Wednesday 2/12/2026",
                "exercises": [{"exercise": "Back Squat", "load": "110 kg"}],
            },
            {
                "sheet_name": "Weekly Plan (2/17/2026)",
                "date": "Monday 2/17/2026",
                "exercises": [{"exercise": "Back Squat", "load": "120 kg"}],
            },
        ]

        progression = analytics.get_main_lift_progression("squat", weeks=8)

        self.assertIsNotNone(progression)
        self.assertEqual(progression["starting_load"], 100.0)
        self.assertEqual(progression["current_load"], 120.0)
        self.assertEqual(progression["progression_kg"], 20.0)

    def test_weekly_volume_aggregates_by_sheet_not_day(self):
        analytics = WorkoutAnalytics(sheets_reader=None)
        analytics.historical_data = [
            {
                "sheet_name": "Weekly Plan (2/10/2026)",
                "date": "Monday 2/10/2026",
                "exercises": [{"exercise": "Back Squat", "sets": "3", "reps": "5", "load": "100 kg"}],
            },
            {
                "sheet_name": "Weekly Plan (2/10/2026)",
                "date": "Wednesday 2/12/2026",
                "exercises": [{"exercise": "Back Squat", "sets": "3", "reps": "5", "load": "110 kg"}],
            },
            {
                "sheet_name": "Weekly Plan (2/17/2026)",
                "date": "Monday 2/17/2026",
                "exercises": [{"exercise": "Back Squat", "sets": "3", "reps": "5", "load": "120 kg"}],
            },
        ]

        weekly_volume = analytics.get_weekly_volume(weeks=8)

        self.assertEqual(list(weekly_volume.keys()), ["Weekly Plan (2/10/2026)", "Weekly Plan (2/17/2026)"])
        self.assertEqual(weekly_volume["Weekly Plan (2/10/2026)"], 3150.0)
        self.assertEqual(weekly_volume["Weekly Plan (2/17/2026)"], 1800.0)


class ViewPlansParserRegressionTests(unittest.TestCase):
    def test_parse_plan_content_supports_mixed_case_day_headers(self):
        content = """## Monday (Fort Gameday #1)
### A1. Back Squat
- 3 x 5 @ 100 kg
- **Rest:** 180 seconds
- **Notes:** Main lift

## Wednesday
### A1. Bench Press
- 3 x 5 @ 80 kg
- **Rest:** 180 seconds
- **Notes:** Main lift
"""
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as temp_file:
            temp_file.write(content)
            temp_path = temp_file.name

        try:
            days = parse_plan_content(temp_path)
        finally:
            os.remove(temp_path)

        self.assertIn("MONDAY", days)
        self.assertIn("WEDNESDAY", days)
        self.assertIn("Back Squat", days["MONDAY"])
        self.assertIn("Bench Press", days["WEDNESDAY"])


if __name__ == "__main__":
    unittest.main()
