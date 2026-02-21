import unittest

from src.fort_compiler import (
    build_fort_compiler_context,
    find_first_section_index,
    parse_fort_day,
    repair_plan_fort_anchors,
    validate_fort_fidelity,
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

MINIMAL_SAMPLE = """
Monday 1.01.26
Mini Cycle
WARM UP
PUSH UPS
BARBELL BREAKPOINT
BACK SQUAT
THAW PREP
ROWERG
"""

TEST_WEEK_SAMPLE = """
Monday 2.23.26
Testing Day #1
PREP
AIR SQUAT
JUMP SQUAT
1RM TEST
BACK SQUAT
BACK OFF SETS
BACK SQUAT
GARAGE - 2K BIKEERG
AUXILIARY/RECOVERY
SINGLE ARM DB ROW
DB RDL (GLUTE OPTIMIZED)
"""

TEST_WEEK_SPLIT_SQUAT_SAMPLE = """
Wednesday 2.25.26
Testing Day #2
TARGETED WARM-UP
CLOSE GRIP PUSH UP
PLYO PUSH-UP
1RM TEST
BENCH PRESS
BACK OFF SETS
BENCH PRESS
GARAGE/UG/UES/WB - 2K ROW TEST
AUXILIARY/RECOVERY
DB SPLIT SQUAT
SLIDER ROLLOUTS
"""

TEST_WEEK_NOISE_SAMPLE = """
Monday 2.23.26
Testing Day #1
PREP
AIR SQUAT
JUMP SQUAT
COMPLETE
1RM TEST
BACK SQUAT
BACK OFF SETS
BACK SQUAT
GARAGE - 2K BIKEERG
TIPS
Rest 2 minutes.
Right into...
Rest 3 minutes.
2k BikeErg for time.
AUXILIARY/RECOVERY
SINGLE ARM DB ROW
DB RDL (GLUTE OPTIMIZED)
"""

TEST_WEEK_COMPLETE_SECTION_PREFIX_SAMPLE = """
Monday 2.23.26
PREP
AIR SQUAT
COMPLETE GARAGE - 2K BIKEERG
"""

TEST_WEEK_PRIORITY_SAMPLE = """
Monday 2.23.26
Testing Day #1
THE PRIORITY IS THE HEAVY SINGLE (OR TRIPLE) AND THE CONDITIONING BENCHMARK. BACK OFF SETS AND AUXILIARY ARE ALL TO BE DONE TIME PERMITTING.
PREP
AIR SQUAT
JUMP SQUAT
1RM TEST
BACK SQUAT
BACK OFF SETS
BACK SQUAT
GARAGE - 2K BIKEERG
AUXILIARY/RECOVERY
SINGLE ARM DB ROW
DB RDL (GLUTE OPTIMIZED)
"""

TEST_WEEK_BULGARIAN_SAMPLE = """
Friday 2.27.26
Testing Day #3
AUXILIARY/RECOVERY
BULGARIAN SPLIT SQUAT (CONTRALATERAL)
15° DB BENCH PRESS
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

    def test_validate_fort_fidelity_detects_missing_anchor(self):
        _context, metadata = build_fort_compiler_context(
            {"Monday": MINIMAL_SAMPLE, "Wednesday": "", "Friday": ""}
        )
        generated_plan = """## MONDAY
### A1. Push Ups
- 1 x 20 @ 0 kg
- **Rest:** None
- **Notes:** Bodyweight breakpoint set.
### B1. Back Squat
- 4 x 8 @ 80 kg
- **Rest:** 120 seconds
- **Notes:** Main lift.
"""
        fidelity = validate_fort_fidelity(generated_plan, metadata)
        codes = {violation["code"] for violation in fidelity["violations"]}
        self.assertIn("fort_missing_anchor", codes)

    def test_validate_fort_fidelity_passes_with_alias_match(self):
        context, metadata = build_fort_compiler_context(
            {"Monday": MINIMAL_SAMPLE, "Wednesday": "", "Friday": ""}
        )
        self.assertIn("FORT COMPILER DIRECTIVES", context)
        generated_plan = """## MONDAY
### A1. Push Ups
- 1 x 20 @ 0 kg
- **Rest:** None
- **Notes:** Bodyweight breakpoint set.
### B1. Back Squat
- 4 x 8 @ 80 kg
- **Rest:** 120 seconds
- **Notes:** Main lift.
### C1. Rower
- 1 x 45 @ 0 kg
- **Rest:** 45 seconds
- **Notes:** THAW prep.
"""
        fidelity = validate_fort_fidelity(
            generated_plan,
            metadata,
            exercise_aliases={"ROWERG": "Rower"},
        )
        codes = {violation["code"] for violation in fidelity["violations"]}
        self.assertNotIn("fort_missing_anchor", codes)

    def test_repair_plan_fort_anchors_inserts_missing_anchor(self):
        _context, metadata = build_fort_compiler_context(
            {"Monday": MINIMAL_SAMPLE, "Wednesday": "", "Friday": ""}
        )
        generated_plan = """## MONDAY
### A1. Push Ups
- 1 x 20 @ 0 kg
- **Rest:** None
- **Notes:** Bodyweight breakpoint set.
### B1. Back Squat
- 4 x 8 @ 80 kg
- **Rest:** 120 seconds
- **Notes:** Main lift.
"""
        repaired, repair_summary = repair_plan_fort_anchors(generated_plan, metadata)
        self.assertGreaterEqual(repair_summary["inserted"], 1)
        self.assertIn("ROWERG", repaired.upper())
        self.assertRegex(repaired, r"-\s*\d+\s*x\s*[\d:]+\s*@\s*[\d.]+\s*kg")

        fidelity = validate_fort_fidelity(repaired, metadata)
        codes = {violation["code"] for violation in fidelity["violations"]}
        self.assertNotIn("fort_missing_anchor", codes)
        self.assertIn("fort_placeholder_prescription", codes)

    def test_repair_plan_fort_anchors_adds_missing_day(self):
        _context, metadata = build_fort_compiler_context(
            {"Monday": MINIMAL_SAMPLE, "Wednesday": MINIMAL_SAMPLE, "Friday": ""}
        )
        generated_plan = """## MONDAY
### A1. Push Ups
- 1 x 20 @ 0 kg
- **Rest:** None
- **Notes:** Bodyweight breakpoint set.
"""
        repaired, repair_summary = repair_plan_fort_anchors(generated_plan, metadata)
        self.assertGreaterEqual(repair_summary["inserted"], 1)
        self.assertIn("## WEDNESDAY", repaired)

        fidelity = validate_fort_fidelity(repaired, metadata)
        codes = {violation["code"] for violation in fidelity["violations"]}
        self.assertNotIn("fort_day_missing", codes)
        self.assertNotIn("fort_missing_anchor", codes)
        self.assertIn("fort_placeholder_prescription", codes)

    def test_repair_plan_fort_anchors_rebuilds_day_and_drops_noise_rows(self):
        _context, metadata = build_fort_compiler_context(
            {"Monday": TEST_WEEK_SAMPLE, "Wednesday": "", "Friday": ""}
        )
        generated_plan = """## MONDAY
### F1. Targeted Warm-Up
- 1 x 1 @ 0 kg
- **Rest:** None
- **Notes:** Noise row.
### G1. AIR SQUAT
- 2 x 1:00 @ 0 kg
- **Rest:** 60 seconds
- **Notes:** Primer.
### G2. JUMP SQUAT
- 2 x 5 @ 0 kg
- **Rest:** 60 seconds
- **Notes:** Primer.
### H1. BACK SQUAT
- 1 x 10 @ 26 kg
- **Rest:** 180 seconds
- **Notes:** Build to test.
### J1. GARAGE - 2K BIKEERG
- 2 x 0:20 @ 0 kg
- **Rest:** None
- **Notes:** Conditioning benchmark.
### J2. TIPS
- 1 x 1 @ 0 kg
- **Rest:** None
- **Notes:** Noise row.
### K1. SINGLE ARM DB ROW
- 3 x 8 @ 28 kg
- **Rest:** 90 seconds
- **Notes:** Time permitting.
### K2. DB RDL (GLUTE OPTIMIZED)
- 3 x 8 @ 26 kg
- **Rest:** 90 seconds
- **Notes:** Time permitting.
"""
        repaired, repair_summary = repair_plan_fort_anchors(generated_plan, metadata)
        self.assertGreaterEqual(repair_summary["dropped"], 1)
        self.assertNotIn("### F1. Targeted Warm-Up", repaired)
        self.assertNotIn("### J2. TIPS", repaired)
        self.assertIn("### A1. AIR SQUAT", repaired)
        self.assertIn("### F1. GARAGE - 2K BIKEERG", repaired)

    def test_parse_fort_day_handles_test_week_headers(self):
        parsed = parse_fort_day("Monday", TEST_WEEK_SAMPLE)
        section_ids = [section["section_id"] for section in parsed["sections"]]
        self.assertIn("prep_mobility", section_ids)
        self.assertIn("strength_work", section_ids)
        self.assertIn("strength_backoff", section_ids)
        self.assertIn("conditioning", section_ids)
        self.assertIn("auxiliary_hypertrophy", section_ids)

        all_exercises = {
            exercise
            for section in parsed["sections"]
            for exercise in section["exercises"]
        }
        self.assertIn("BACK SQUAT", all_exercises)
        self.assertIn("GARAGE - 2K BIKEERG", all_exercises)
        self.assertNotIn("1RM TEST", all_exercises)
        self.assertNotIn("BACK OFF SETS", all_exercises)

    def test_parse_fort_day_filters_instruction_lines_from_anchors(self):
        parsed = parse_fort_day("Monday", TEST_WEEK_NOISE_SAMPLE)
        all_exercises = {
            exercise
            for section in parsed["sections"]
            for exercise in section["exercises"]
        }
        self.assertIn("GARAGE - 2K BIKEERG", all_exercises)
        self.assertNotIn("TIPS", all_exercises)
        self.assertNotIn("Rest 2 minutes.", all_exercises)
        self.assertNotIn("Right into...", all_exercises)
        self.assertNotIn("COMPLETE GARAGE - 2K BIKEERG", all_exercises)
        self.assertIn("GARAGE - 2K BIKEERG", all_exercises)

    def test_parse_fort_day_strips_complete_prefix_from_section_line(self):
        parsed = parse_fort_day("Monday", TEST_WEEK_COMPLETE_SECTION_PREFIX_SAMPLE)
        all_exercises = {
            exercise
            for section in parsed["sections"]
            for exercise in section["exercises"]
        }
        self.assertIn("GARAGE - 2K BIKEERG", all_exercises)
        self.assertNotIn("COMPLETE GARAGE - 2K BIKEERG", all_exercises)

    def test_parse_fort_day_does_not_treat_priority_narrative_as_section(self):
        parsed = parse_fort_day("Monday", TEST_WEEK_PRIORITY_SAMPLE)
        section_headers = [section["raw_header"] for section in parsed["sections"]]
        self.assertNotIn(
            "THE PRIORITY IS THE HEAVY SINGLE (OR TRIPLE) AND THE CONDITIONING BENCHMARK. BACK OFF SETS AND AUXILIARY ARE ALL TO BE DONE TIME PERMITTING.",
            section_headers,
        )

    def test_validate_fort_fidelity_handles_split_squat_swap_alias(self):
        _context, metadata = build_fort_compiler_context(
            {"Monday": "", "Wednesday": TEST_WEEK_SPLIT_SQUAT_SAMPLE, "Friday": ""}
        )
        generated_plan = """## WEDNESDAY
### A1. Close Grip Push Up
- 2 x 10 @ 0 kg
- **Rest:** 60 seconds
- **Notes:** Primer.
### A2. Plyo Push-Up
- 2 x 5 @ 0 kg
- **Rest:** 60 seconds
- **Notes:** Primer.
### C1. Bench Press
- 1 x 1 @ 90 kg
- **Rest:** 180 seconds
- **Notes:** 1RM test.
### D1. Bench Press
- 2 x 5 @ 70 kg
- **Rest:** 120 seconds
- **Notes:** Back-off sets.
### F1. 2K Row Test
- 1 x 1 @ 0 kg
- **Rest:** None
- **Notes:** Conditioning test.
### G1. Heel-Elevated Goblet Squat
- 3 x 8 @ 24 kg
- **Rest:** 90 seconds
- **Notes:** Split squat swap rule applied.
### G2. Slider Rollouts
- 3 x 8 @ 0 kg
- **Rest:** 60 seconds
- **Notes:** Core.
"""
        fidelity = validate_fort_fidelity(
            generated_plan,
            metadata,
            exercise_aliases={"Split Squat": "Heel-Elevated Goblet Squat"},
        )
        codes = {violation["code"] for violation in fidelity["violations"]}
        self.assertNotIn("fort_missing_anchor", codes)

    def test_validate_fort_fidelity_split_squat_alias_not_overbroad(self):
        _context, metadata = build_fort_compiler_context(
            {"Monday": "", "Wednesday": TEST_WEEK_SPLIT_SQUAT_SAMPLE, "Friday": ""}
        )
        generated_plan = """## WEDNESDAY
### A1. Close Grip Push Up
- 2 x 10 @ 0 kg
- **Rest:** 60 seconds
- **Notes:** Primer.
### A2. Plyo Push-Up
- 2 x 5 @ 0 kg
- **Rest:** 60 seconds
- **Notes:** Primer.
### C1. Bench Press
- 1 x 1 @ 90 kg
- **Rest:** 180 seconds
- **Notes:** 1RM test.
### D1. Bench Press
- 2 x 5 @ 70 kg
- **Rest:** 120 seconds
- **Notes:** Back-off sets.
### F1. 2K Row Test
- 1 x 1 @ 0 kg
- **Rest:** None
- **Notes:** Conditioning test.
### G1. Leg Extension
- 3 x 10 @ 45 kg
- **Rest:** 90 seconds
- **Notes:** Not a valid split squat swap target for generic split squat.
### G2. Slider Rollouts
- 3 x 8 @ 0 kg
- **Rest:** 60 seconds
- **Notes:** Core.
"""
        fidelity = validate_fort_fidelity(
            generated_plan,
            metadata,
            exercise_aliases={
                "Split Squat": "Heel-Elevated Goblet Squat",
                "Forward Split Squat": "Leg Extension",
            },
        )
        codes = {violation["code"] for violation in fidelity["violations"]}
        self.assertIn("fort_missing_anchor", codes)

    def test_validate_fort_fidelity_handles_bulgarian_swap_alias_with_variant_suffix(self):
        _context, metadata = build_fort_compiler_context(
            {"Monday": "", "Wednesday": "", "Friday": TEST_WEEK_BULGARIAN_SAMPLE}
        )
        generated_plan = """## FRIDAY
### G1. Heel-Elevated Goblet Squat (CONTRALATERAL)
- 3 x 8 @ 20 kg
- **Rest:** 90 seconds
- **Notes:** Split squat swap rule applied.
### G2. 15° DB Bench Press
- 3 x 8 @ 26 kg
- **Rest:** 90 seconds
- **Notes:** Upper chest.
"""
        fidelity = validate_fort_fidelity(
            generated_plan,
            metadata,
            exercise_aliases={"Bulgarian Split Squat": "Heel-Elevated Goblet Squat"},
        )
        codes = {violation["code"] for violation in fidelity["violations"]}
        self.assertNotIn("fort_missing_anchor", codes)


if __name__ == "__main__":
    unittest.main()
