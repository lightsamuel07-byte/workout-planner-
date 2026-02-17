import unittest

from src.fort_compiler import (
    build_fort_compiler_context,
    find_first_section_index,
    parse_fort_day,
)


DEVIL_DAY_SAMPLE = """
Monday 1.12.26
The Devil You Know #7
Ignition:
Our opening section focuses on activation and pre-hab.

  IGNITION - KOT WARM-UP
Perform as many rounds of this superset as possible for 5 minutes.
KNEE TO WALL STRETCH
CALF RAISE TO TIBIALIS RAISE
KNEE OVER TOE SPLIT SQUAT
COMPLETE
  FANNING THE FLAMES - POWER
BOX JUMP
COMPLETE
  THE CAULDRON -  BUILD UP
BACK SQUAT
COMPLETE
  THE CAULDRON - WORKING SET
BACK SQUAT
  THE CAULDRON - BACK OFFS
BACK SQUAT
  IT BURNS - UPPER BODY AUX
SINGLE ARM DB ROW
DB LATERAL SHOULDER RAISE
PUSH UPS
  REDEMPTION - MAXIMUM POWER
ROWERG
"""


BREAKPOINT_SAMPLE = """
Monday 12.01.25
The Breakpoint #1
The relentless pursuit of the only rep that matters.

  WARM UP
HAND RELEASE PUSH-UP
AIR SQUAT
COMPLETE
  BODYWEIGHT BREAKPOINT
PUSH UPS
  BARBELL BREAKPOINT
BACK SQUAT
  AUXILIARY
CHEST SUPPORTED DB ROW
ROLLER HAMSTRING CURL
AB ROLLOUT
  DUMBBELL BREAKPOINT
CHEST SUPPORTED DB ROW
  THAW PREP
ROWERG
  THAW BREAKPOINT
ROWERG
"""


class FortCompilerTests(unittest.TestCase):
    def test_find_first_section_index_skips_narrative_lines(self):
        lines = DEVIL_DAY_SAMPLE.splitlines()
        index = find_first_section_index(lines)
        self.assertIsNotNone(index)
        self.assertIn("IGNITION - KOT WARM-UP", lines[index])

    def test_parse_fort_day_handles_non_cluster_program(self):
        parsed = parse_fort_day("Monday", DEVIL_DAY_SAMPLE)
        section_ids = [section["section_id"] for section in parsed["sections"]]

        self.assertIn("prep_mobility", section_ids)
        self.assertIn("power_activation", section_ids)
        self.assertIn("strength_build", section_ids)
        self.assertIn("strength_work", section_ids)
        self.assertIn("strength_backoff", section_ids)
        self.assertIn("auxiliary_hypertrophy", section_ids)
        self.assertIn("conditioning", section_ids)

        all_exercises = {
            exercise
            for section in parsed["sections"]
            for exercise in section["exercises"]
        }
        self.assertIn("BACK SQUAT", all_exercises)
        self.assertIn("BOX JUMP", all_exercises)
        self.assertIn("ROWERG", all_exercises)

    def test_parse_fort_day_handles_breakpoint_program(self):
        parsed = parse_fort_day("Monday", BREAKPOINT_SAMPLE)
        section_ids = [section["section_id"] for section in parsed["sections"]]
        self.assertIn("prep_mobility", section_ids)
        self.assertIn("strength_work", section_ids)
        self.assertIn("auxiliary_hypertrophy", section_ids)
        self.assertIn("conditioning", section_ids)
        self.assertGreater(parsed["confidence"], 0.5)

    def test_build_fort_compiler_context_includes_day_summaries(self):
        context, metadata = build_fort_compiler_context(
            {
                "Monday": DEVIL_DAY_SAMPLE,
                "Wednesday": BREAKPOINT_SAMPLE,
                "Friday": DEVIL_DAY_SAMPLE,
            }
        )
        self.assertIn("FORT COMPILER DIRECTIVES", context)
        self.assertIn("MONDAY", context)
        self.assertIn("WEDNESDAY", context)
        self.assertIn("FRIDAY", context)
        self.assertGreater(metadata["overall_confidence"], 0.5)


if __name__ == "__main__":
    unittest.main()
