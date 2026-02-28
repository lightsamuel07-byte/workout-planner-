"""Tests for the ExerciseNormalizer engine."""

import unittest

from src.exercise_normalizer import ExerciseNormalizer, reset_normalizer


class TestCanonicalKey(unittest.TestCase):
    """Test canonical key computation (stripping, abbreviation, etc.)."""

    def setUp(self):
        reset_normalizer()
        self.n = ExerciseNormalizer(swaps_file="exercise_swaps.yaml")

    def test_warmup_set_stripped(self):
        self.assertEqual(
            self.n.canonical_key("Back Squat (Warm-up Set 3)"),
            self.n.canonical_key("Back Squat"),
        )

    def test_cluster_qualifier_stripped(self):
        self.assertEqual(
            self.n.canonical_key("Back Squat (Cluster Singles)"),
            self.n.canonical_key("Back Squat"),
        )

    def test_build_working_backoff_stripped(self):
        base = self.n.canonical_key("Bench Press")
        self.assertEqual(self.n.canonical_key("Bench Press (Build)"), base)
        self.assertEqual(self.n.canonical_key("Bench Press (Working)"), base)
        self.assertEqual(self.n.canonical_key("Bench Press (Back-off)"), base)

    def test_breakpoint_dash_suffix_stripped(self):
        self.assertEqual(
            self.n.canonical_key("Back Squat (paused) — BREAKPOINT"),
            self.n.canonical_key("Back Squat (paused)"),
        )
        self.assertEqual(
            self.n.canonical_key("Barbell Row (paused) — calibration"),
            self.n.canonical_key("Barbell Row (paused)"),
        )

    def test_emom_max_stripped(self):
        self.assertEqual(
            self.n.canonical_key("Box Jump (EMOM)"),
            self.n.canonical_key("Box Jump"),
        )
        self.assertEqual(
            self.n.canonical_key("Pull-Ups (max)"),
            self.n.canonical_key("Pull-Up"),
        )

    def test_myo_rep_stripped(self):
        self.assertEqual(
            self.n.canonical_key("DB Sumo Squat (LAST SET = MYO-REP)"),
            self.n.canonical_key("DB Sumo Squat"),
        )

    def test_ez_bar_unification(self):
        key = self.n.canonical_key("EZ-Bar Curl")
        self.assertEqual(self.n.canonical_key("EZ Bar Curl"), key)
        self.assertEqual(self.n.canonical_key("Ez bar Curl"), key)

    def test_bikeerg_unification(self):
        key = self.n.canonical_key("BikeErg")
        self.assertEqual(self.n.canonical_key("Bike Erg"), key)

    def test_skierg_unification(self):
        key = self.n.canonical_key("SkiErg")
        self.assertEqual(self.n.canonical_key("Ski Erg"), key)

    def test_depluralization(self):
        self.assertEqual(
            self.n.canonical_key("Side-Lying Windmills"),
            self.n.canonical_key("Side-Lying Windmill"),
        )
        self.assertEqual(
            self.n.canonical_key("Pull-Ups"),
            self.n.canonical_key("Pull-Up"),
        )

    def test_empty_and_none(self):
        self.assertEqual(self.n.canonical_key(""), "")
        self.assertEqual(self.n.canonical_key(None), "")

    def test_second_set_stripped(self):
        self.assertEqual(
            self.n.canonical_key("90/90 Hip Switch (Second Set)"),
            self.n.canonical_key("90/90 Hip Switch"),
        )


class TestIdentityPreservingQualifiers(unittest.TestCase):
    """Qualifiers that change exercise identity must NOT be stripped."""

    def setUp(self):
        reset_normalizer()
        self.n = ExerciseNormalizer(swaps_file="exercise_swaps.yaml")

    def test_supinated_preserved(self):
        self.assertNotEqual(
            self.n.canonical_key("Incline DB Curl (Supinated)"),
            self.n.canonical_key("Incline DB Curl"),
        )

    def test_angle_preserved(self):
        self.assertNotEqual(
            self.n.canonical_key("30° Incline DB Press"),
            self.n.canonical_key("45° Incline DB Press"),
        )

    def test_paused_variant_preserved(self):
        # "Back Squat (paused)" is different from "Back Squat"
        self.assertNotEqual(
            self.n.canonical_key("Back Squat (paused)"),
            self.n.canonical_key("Back Squat"),
        )

    def test_glute_optimized_preserved(self):
        # Glute optimized is an identity qualifier
        key = self.n.canonical_key("DB RDL (Glute Optimized)")
        self.assertIn("glute", key)


class TestAreSameExercise(unittest.TestCase):
    """Test the main identity comparison method."""

    def setUp(self):
        reset_normalizer()
        self.n = ExerciseNormalizer(swaps_file="exercise_swaps.yaml")

    def test_exact_match(self):
        self.assertTrue(self.n.are_same_exercise("Back Squat", "Back Squat"))

    def test_alias_group_match(self):
        self.assertTrue(
            self.n.are_same_exercise("DB RDL (Glute Optimized)", "DB RDL (glute-opt.)")
        )

    def test_heel_elevated_variants(self):
        self.assertTrue(
            self.n.are_same_exercise(
                "Heel-Elevated DB Goblet Squat",
                "Heels-Elevated DB Goblet Squat",
            )
        )

    def test_warmup_set_matches_base(self):
        self.assertTrue(
            self.n.are_same_exercise("Back Squat (Warm-up Set 3)", "Back Squat")
        )

    def test_face_pull_family(self):
        self.assertTrue(
            self.n.are_same_exercise("Face Pull (rope)", "Cable Face Pull (rope)")
        )
        self.assertTrue(
            self.n.are_same_exercise("Face Pulls", "Face Pull (Rope)")
        )

    def test_standing_calf_raise_variants(self):
        self.assertTrue(
            self.n.are_same_exercise(
                "Standing Calf Raise",
                "Standing Calf Raise (Machine)",
            )
        )

    def test_bench_equals_bench_press(self):
        self.assertTrue(
            self.n.are_same_exercise("Bench (paused)", "Bench Press (paused)")
        )

    def test_db_hammer_curl_variants(self):
        self.assertTrue(
            self.n.are_same_exercise("DB Hammer Curl", "DB Hammer Curl (neutral)")
        )

    def test_poliquin_step_up_variants(self):
        self.assertTrue(
            self.n.are_same_exercise("Poliquin Step-Up", "Poliquin step up")
        )

    def test_symmetry(self):
        a, b = "DB RDL (Glute Optimized)", "DB RDL (glute-opt.)"
        self.assertEqual(
            self.n.are_same_exercise(a, b),
            self.n.are_same_exercise(b, a),
        )

    def test_none_and_empty(self):
        self.assertFalse(self.n.are_same_exercise("", "Back Squat"))
        self.assertFalse(self.n.are_same_exercise(None, "Back Squat"))
        self.assertFalse(self.n.are_same_exercise(None, None))


class TestCrossBodyPartSafety(unittest.TestCase):
    """Fuzzy matching must NOT match across different body parts."""

    def setUp(self):
        reset_normalizer()
        self.n = ExerciseNormalizer(swaps_file="exercise_swaps.yaml")

    def test_curl_does_not_match_press(self):
        self.assertFalse(self.n.are_same_exercise("DB Curl", "DB Press"))

    def test_squat_does_not_match_deadlift(self):
        self.assertFalse(self.n.are_same_exercise("Back Squat", "Deadlift"))

    def test_row_does_not_match_press(self):
        self.assertFalse(self.n.are_same_exercise("Barbell Row", "Bench Press"))

    def test_tricep_does_not_match_bicep(self):
        self.assertFalse(
            self.n.are_same_exercise("Tricep Pushdown (Rope)", "DB Hammer Curl")
        )


class TestCanonicalName(unittest.TestCase):
    """Test canonical display name resolution."""

    def setUp(self):
        reset_normalizer()
        self.n = ExerciseNormalizer(swaps_file="exercise_swaps.yaml")

    def test_known_alias_returns_canonical(self):
        self.assertEqual(
            self.n.canonical_name("DB RDL (glute-opt.)"),
            "DB RDL (Glute Optimized)",
        )

    def test_poliquin_canonical(self):
        self.assertEqual(
            self.n.canonical_name("Poliquin step up"),
            "Poliquin Step-Up",
        )

    def test_warmup_stripped_in_display(self):
        display = self.n.canonical_name("Deadlift (Warm-up Set 2)")
        self.assertNotIn("Warm-up", display)
        self.assertIn("Deadlift", display)

    def test_unknown_exercise_returns_cleaned(self):
        # Unknown exercise should return itself, cleaned
        result = self.n.canonical_name("Some Brand New Exercise")
        self.assertEqual(result, "Some Brand New Exercise")


class TestFindMatch(unittest.TestCase):
    """Test finding the best match from a candidate list."""

    def setUp(self):
        reset_normalizer()
        self.n = ExerciseNormalizer(swaps_file="exercise_swaps.yaml")

    def test_exact_match_in_candidates(self):
        candidates = ["Back Squat", "Bench Press", "Deadlift"]
        self.assertEqual(
            self.n.find_match("Back Squat (Working)", candidates),
            "Back Squat",
        )

    def test_alias_match_in_candidates(self):
        candidates = ["DB RDL (Glute Optimized)", "Bench Press"]
        self.assertEqual(
            self.n.find_match("DB RDL (glute-opt.)", candidates),
            "DB RDL (Glute Optimized)",
        )

    def test_no_match_returns_none(self):
        candidates = ["Back Squat", "Bench Press"]
        self.assertIsNone(self.n.find_match("Cable Lateral Raise", candidates))

    def test_empty_candidates(self):
        self.assertIsNone(self.n.find_match("Back Squat", []))


class TestExerciseTypeDetection(unittest.TestCase):
    """Test DB exercise and main lift detection."""

    def setUp(self):
        reset_normalizer()
        self.n = ExerciseNormalizer(swaps_file="exercise_swaps.yaml")

    def test_db_exercise_detection(self):
        self.assertTrue(self.n.is_db_exercise("DB Hammer Curl"))
        self.assertTrue(self.n.is_db_exercise("Incline DB Press"))
        self.assertTrue(self.n.is_db_exercise("Dumbbell Lateral Raise"))
        self.assertFalse(self.n.is_db_exercise("Back Squat"))
        self.assertFalse(self.n.is_db_exercise("Cable Lateral Raise"))

    def test_main_plate_lift_detection(self):
        self.assertTrue(self.n.is_main_plate_lift("Back Squat"))
        self.assertTrue(self.n.is_main_plate_lift("Bench Press"))
        self.assertTrue(self.n.is_main_plate_lift("Deadlift"))
        self.assertFalse(self.n.is_main_plate_lift("DB Lateral Raise"))
        self.assertFalse(self.n.is_main_plate_lift("Cable Lateral Raise"))


class TestSwapIntegration(unittest.TestCase):
    """Test that exercise_swaps.yaml aliases are registered."""

    def setUp(self):
        reset_normalizer()
        self.n = ExerciseNormalizer(swaps_file="exercise_swaps.yaml")

    def test_seated_calf_maps_to_standing(self):
        # exercise_swaps.yaml: "Seated Calf Raise" -> "Standing Calf Raise"
        self.assertTrue(
            self.n.are_same_exercise("Seated Calf Raise", "Standing Calf Raise")
        )

    def test_split_squat_is_not_auto_swapped(self):
        # Split squats are no longer auto-swapped. Fort-trainer-programmed
        # split squats must be preserved on Mon/Wed/Fri.
        canonical = self.n.canonical_name("Bulgarian Split Squat")
        self.assertEqual(canonical, "Bulgarian Split Squat")


class TestRegisterAlias(unittest.TestCase):
    """Test runtime alias registration."""

    def setUp(self):
        reset_normalizer()
        self.n = ExerciseNormalizer(swaps_file="exercise_swaps.yaml")

    def test_register_new_alias(self):
        self.assertFalse(
            self.n.are_same_exercise("My Custom Press", "Bench Press")
        )
        self.n.register_alias("My Custom Press", "Bench Press")
        self.assertTrue(
            self.n.are_same_exercise("My Custom Press", "Bench Press")
        )


if __name__ == "__main__":
    unittest.main()
