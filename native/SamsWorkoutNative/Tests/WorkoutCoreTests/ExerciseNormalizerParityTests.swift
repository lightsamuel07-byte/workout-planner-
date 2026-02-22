import Foundation
import XCTest
@testable import WorkoutCore

private func repoSwapsFilePath() -> String {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let repoRoot = packageRoot
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("exercise_swaps.yaml").path
}

class ExerciseNormalizerTestCase: XCTestCase {
    var normalizer: ExerciseNormalizer!

    override func setUp() {
        super.setUp()
        resetNormalizer()
        let swapsPath = repoSwapsFilePath()
        XCTAssertTrue(FileManager.default.fileExists(atPath: swapsPath), "Missing swaps file at \(swapsPath)")
        normalizer = ExerciseNormalizer(swapsFile: swapsPath)
    }
}

final class CanonicalKeyParityTests: ExerciseNormalizerTestCase {
    func testWarmupSetStripped() {
        XCTAssertEqual(
            normalizer.canonicalKey("Back Squat (Warm-up Set 3)"),
            normalizer.canonicalKey("Back Squat")
        )
    }

    func testClusterQualifierStripped() {
        XCTAssertEqual(
            normalizer.canonicalKey("Back Squat (Cluster Singles)"),
            normalizer.canonicalKey("Back Squat")
        )
    }

    func testBuildWorkingBackoffStripped() {
        let base = normalizer.canonicalKey("Bench Press")
        XCTAssertEqual(normalizer.canonicalKey("Bench Press (Build)"), base)
        XCTAssertEqual(normalizer.canonicalKey("Bench Press (Working)"), base)
        XCTAssertEqual(normalizer.canonicalKey("Bench Press (Back-off)"), base)
    }

    func testBreakpointDashSuffixStripped() {
        XCTAssertEqual(
            normalizer.canonicalKey("Back Squat (paused) — BREAKPOINT"),
            normalizer.canonicalKey("Back Squat (paused)")
        )
        XCTAssertEqual(
            normalizer.canonicalKey("Barbell Row (paused) — calibration"),
            normalizer.canonicalKey("Barbell Row (paused)")
        )
    }

    func testEmomMaxStripped() {
        XCTAssertEqual(
            normalizer.canonicalKey("Box Jump (EMOM)"),
            normalizer.canonicalKey("Box Jump")
        )
        XCTAssertEqual(
            normalizer.canonicalKey("Pull-Ups (max)"),
            normalizer.canonicalKey("Pull-Up")
        )
    }

    func testMyoRepStripped() {
        XCTAssertEqual(
            normalizer.canonicalKey("DB Sumo Squat (LAST SET = MYO-REP)"),
            normalizer.canonicalKey("DB Sumo Squat")
        )
    }

    func testEzBarUnification() {
        let key = normalizer.canonicalKey("EZ-Bar Curl")
        XCTAssertEqual(normalizer.canonicalKey("EZ Bar Curl"), key)
        XCTAssertEqual(normalizer.canonicalKey("Ez bar Curl"), key)
    }

    func testBikeergUnification() {
        let key = normalizer.canonicalKey("BikeErg")
        XCTAssertEqual(normalizer.canonicalKey("Bike Erg"), key)
    }

    func testSkiergUnification() {
        let key = normalizer.canonicalKey("SkiErg")
        XCTAssertEqual(normalizer.canonicalKey("Ski Erg"), key)
    }

    func testDepluralization() {
        XCTAssertEqual(
            normalizer.canonicalKey("Side-Lying Windmills"),
            normalizer.canonicalKey("Side-Lying Windmill")
        )
        XCTAssertEqual(
            normalizer.canonicalKey("Pull-Ups"),
            normalizer.canonicalKey("Pull-Up")
        )
    }

    func testEmptyAndNone() {
        XCTAssertEqual(normalizer.canonicalKey(""), "")
        XCTAssertEqual(normalizer.canonicalKey(nil), "")
    }

    func testSecondSetStripped() {
        XCTAssertEqual(
            normalizer.canonicalKey("90/90 Hip Switch (Second Set)"),
            normalizer.canonicalKey("90/90 Hip Switch")
        )
    }
}

final class IdentityPreservingQualifierParityTests: ExerciseNormalizerTestCase {
    func testSupinatedPreserved() {
        XCTAssertNotEqual(
            normalizer.canonicalKey("Incline DB Curl (Supinated)"),
            normalizer.canonicalKey("Incline DB Curl")
        )
    }

    func testAnglePreserved() {
        XCTAssertNotEqual(
            normalizer.canonicalKey("30° Incline DB Press"),
            normalizer.canonicalKey("45° Incline DB Press")
        )
    }

    func testPausedVariantPreserved() {
        XCTAssertNotEqual(
            normalizer.canonicalKey("Back Squat (paused)"),
            normalizer.canonicalKey("Back Squat")
        )
    }

    func testGluteOptimizedPreserved() {
        let key = normalizer.canonicalKey("DB RDL (Glute Optimized)")
        XCTAssertTrue(key.contains("glute"))
    }
}

final class AreSameExerciseParityTests: ExerciseNormalizerTestCase {
    func testExactMatch() {
        XCTAssertTrue(normalizer.areSameExercise("Back Squat", "Back Squat"))
    }

    func testAliasGroupMatch() {
        XCTAssertTrue(normalizer.areSameExercise("DB RDL (Glute Optimized)", "DB RDL (glute-opt.)"))
    }

    func testHeelElevatedVariants() {
        XCTAssertTrue(
            normalizer.areSameExercise(
                "Heel-Elevated DB Goblet Squat",
                "Heels-Elevated DB Goblet Squat"
            )
        )
    }

    func testWarmupSetMatchesBase() {
        XCTAssertTrue(normalizer.areSameExercise("Back Squat (Warm-up Set 3)", "Back Squat"))
    }

    func testFacePullFamily() {
        XCTAssertTrue(normalizer.areSameExercise("Face Pull (rope)", "Cable Face Pull (rope)"))
        XCTAssertTrue(normalizer.areSameExercise("Face Pulls", "Face Pull (Rope)"))
    }

    func testStandingCalfRaiseVariants() {
        XCTAssertTrue(normalizer.areSameExercise("Standing Calf Raise", "Standing Calf Raise (Machine)"))
    }

    func testBenchEqualsBenchPress() {
        XCTAssertTrue(normalizer.areSameExercise("Bench (paused)", "Bench Press (paused)"))
    }

    func testDbHammerCurlVariants() {
        XCTAssertTrue(normalizer.areSameExercise("DB Hammer Curl", "DB Hammer Curl (neutral)"))
    }

    func testPoliquinStepUpVariants() {
        XCTAssertTrue(normalizer.areSameExercise("Poliquin Step-Up", "Poliquin step up"))
    }

    func testSymmetry() {
        let a = "DB RDL (Glute Optimized)"
        let b = "DB RDL (glute-opt.)"
        XCTAssertEqual(normalizer.areSameExercise(a, b), normalizer.areSameExercise(b, a))
    }

    func testNoneAndEmpty() {
        XCTAssertFalse(normalizer.areSameExercise("", "Back Squat"))
        XCTAssertFalse(normalizer.areSameExercise(nil, "Back Squat"))
        XCTAssertFalse(normalizer.areSameExercise(nil, nil))
    }
}

final class CrossBodyPartSafetyParityTests: ExerciseNormalizerTestCase {
    func testCurlDoesNotMatchPress() {
        XCTAssertFalse(normalizer.areSameExercise("DB Curl", "DB Press"))
    }

    func testSquatDoesNotMatchDeadlift() {
        XCTAssertFalse(normalizer.areSameExercise("Back Squat", "Deadlift"))
    }

    func testRowDoesNotMatchPress() {
        XCTAssertFalse(normalizer.areSameExercise("Barbell Row", "Bench Press"))
    }

    func testTricepDoesNotMatchBicep() {
        XCTAssertFalse(normalizer.areSameExercise("Tricep Pushdown (Rope)", "DB Hammer Curl"))
    }
}

final class CanonicalNameParityTests: ExerciseNormalizerTestCase {
    func testKnownAliasReturnsCanonical() {
        XCTAssertEqual(
            normalizer.canonicalName("DB RDL (glute-opt.)"),
            "DB RDL (Glute Optimized)"
        )
    }

    func testPoliquinCanonical() {
        XCTAssertEqual(normalizer.canonicalName("Poliquin step up"), "Poliquin Step-Up")
    }

    func testWarmupStrippedInDisplay() {
        let display = normalizer.canonicalName("Deadlift (Warm-up Set 2)")
        XCTAssertFalse(display.contains("Warm-up"))
        XCTAssertTrue(display.contains("Deadlift"))
    }

    func testUnknownExerciseReturnsCleaned() {
        let result = normalizer.canonicalName("Some Brand New Exercise")
        XCTAssertEqual(result, "Some Brand New Exercise")
    }
}

final class FindMatchParityTests: ExerciseNormalizerTestCase {
    func testExactMatchInCandidates() {
        let candidates = ["Back Squat", "Bench Press", "Deadlift"]
        XCTAssertEqual(
            normalizer.findMatch("Back Squat (Working)", candidates: candidates),
            "Back Squat"
        )
    }

    func testAliasMatchInCandidates() {
        let candidates = ["DB RDL (Glute Optimized)", "Bench Press"]
        XCTAssertEqual(
            normalizer.findMatch("DB RDL (glute-opt.)", candidates: candidates),
            "DB RDL (Glute Optimized)"
        )
    }

    func testNoMatchReturnsNone() {
        let candidates = ["Back Squat", "Bench Press"]
        XCTAssertNil(normalizer.findMatch("Cable Lateral Raise", candidates: candidates))
    }

    func testEmptyCandidates() {
        XCTAssertNil(normalizer.findMatch("Back Squat", candidates: []))
    }
}

final class ExerciseTypeDetectionParityTests: ExerciseNormalizerTestCase {
    func testDbExerciseDetection() {
        XCTAssertTrue(normalizer.isDBExercise("DB Hammer Curl"))
        XCTAssertTrue(normalizer.isDBExercise("Incline DB Press"))
        XCTAssertTrue(normalizer.isDBExercise("Dumbbell Lateral Raise"))
        XCTAssertFalse(normalizer.isDBExercise("Back Squat"))
        XCTAssertFalse(normalizer.isDBExercise("Cable Lateral Raise"))
    }

    func testMainPlateLiftDetection() {
        XCTAssertTrue(normalizer.isMainPlateLift("Back Squat"))
        XCTAssertTrue(normalizer.isMainPlateLift("Bench Press"))
        XCTAssertTrue(normalizer.isMainPlateLift("Deadlift"))
        XCTAssertFalse(normalizer.isMainPlateLift("DB Lateral Raise"))
        XCTAssertFalse(normalizer.isMainPlateLift("Cable Lateral Raise"))
    }
}

final class SwapIntegrationParityTests: ExerciseNormalizerTestCase {
    func testSeatedCalfMapsToStanding() {
        XCTAssertTrue(normalizer.areSameExercise("Seated Calf Raise", "Standing Calf Raise"))
    }

    func testSplitSquatMapsToGoblet() {
        let canonical = normalizer.canonicalName("Bulgarian Split Squat")
        XCTAssertEqual(canonical, "Heel-Elevated Goblet Squat")
    }
}

final class RegisterAliasParityTests: ExerciseNormalizerTestCase {
    func testRegisterNewAlias() {
        XCTAssertFalse(normalizer.areSameExercise("My Custom Press", "Bench Press"))
        normalizer.registerAlias(rawName: "My Custom Press", canonicalDisplay: "Bench Press")
        XCTAssertTrue(normalizer.areSameExercise("My Custom Press", "Bench Press"))
    }
}
