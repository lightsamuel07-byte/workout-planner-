import XCTest
@testable import WorkoutCore

final class FortCompilerParityTests: XCTestCase {
    private let devilDaySample = """
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

    private let breakpointSample = """
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

    private let minimalSample = """
    Monday 1.01.26
    Mini Cycle
    WARM UP
    PUSH UPS
    BARBELL BREAKPOINT
    BACK SQUAT
    THAW PREP
    ROWERG
    """

    private let testWeekSample = """
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

    private let testWeekSplitSquatSample = """
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

    private let testWeekNoiseSample = """
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

    private let completeSectionPrefixSample = """
    Monday 2.23.26
    PREP
    AIR SQUAT
    COMPLETE GARAGE - 2K BIKEERG
    """

    private let prioritySample = """
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

    private let bulgarianSample = """
    Friday 2.27.26
    Testing Day #3
    AUXILIARY/RECOVERY
    BULGARIAN SPLIT SQUAT (CONTRALATERAL)
    15 DEGREE DB BENCH PRESS
    """

    func testFindFirstSectionIndexSkipsNarrativeLines() {
        let lines = devilDaySample.components(separatedBy: .newlines)
        let index = findFirstSectionIndex(lines: lines)
        XCTAssertNotNil(index)
        XCTAssertTrue(lines[index ?? 0].contains("IGNITION - KOT WARM-UP"))
    }

    func testParseFortDayHandlesNonClusterProgram() {
        let parsed = parseFortDay(dayName: "Monday", workoutText: devilDaySample)
        let sectionIDs = Set(parsed.sections.map(\.sectionID))

        XCTAssertTrue(sectionIDs.contains("prep_mobility"))
        XCTAssertTrue(sectionIDs.contains("power_activation"))
        XCTAssertTrue(sectionIDs.contains("strength_build"))
        XCTAssertTrue(sectionIDs.contains("strength_work"))
        XCTAssertTrue(sectionIDs.contains("strength_backoff"))
        XCTAssertTrue(sectionIDs.contains("auxiliary_hypertrophy"))
        XCTAssertTrue(sectionIDs.contains("conditioning"))

        let allExercises = Set(parsed.sections.flatMap(\.exercises))
        XCTAssertTrue(allExercises.contains("BACK SQUAT"))
        XCTAssertTrue(allExercises.contains("BOX JUMP"))
        XCTAssertTrue(allExercises.contains("ROWERG"))
    }

    func testParseFortDayHandlesBreakpointProgram() {
        let parsed = parseFortDay(dayName: "Monday", workoutText: breakpointSample)
        let sectionIDs = Set(parsed.sections.map(\.sectionID))

        XCTAssertTrue(sectionIDs.contains("prep_mobility"))
        XCTAssertTrue(sectionIDs.contains("strength_work"))
        XCTAssertTrue(sectionIDs.contains("auxiliary_hypertrophy"))
        XCTAssertTrue(sectionIDs.contains("conditioning"))
        XCTAssertGreaterThan(parsed.confidence, 0.5)
    }

    func testBuildFortCompilerContextIncludesDaySummaries() {
        let (context, metadata) = buildFortCompilerContext(
            dayTextMap: [
                "Monday": devilDaySample,
                "Wednesday": breakpointSample,
                "Friday": devilDaySample,
            ]
        )

        XCTAssertTrue(context.contains("FORT COMPILER DIRECTIVES"))
        XCTAssertTrue(context.contains("MONDAY"))
        XCTAssertTrue(context.contains("WEDNESDAY"))
        XCTAssertTrue(context.contains("FRIDAY"))
        XCTAssertGreaterThan(metadata.overallConfidence, 0.5)
    }

    func testValidateFortFidelityDetectsMissingAnchor() {
        let (_, metadata) = buildFortCompilerContext(dayTextMap: ["Monday": minimalSample, "Wednesday": "", "Friday": ""])
        let generatedPlan = """
        ## MONDAY
        ### A1. Push Ups
        - 1 x 20 @ 0 kg
        - **Rest:** None
        - **Notes:** Bodyweight breakpoint set.
        ### B1. Back Squat
        - 4 x 8 @ 80 kg
        - **Rest:** 120 seconds
        - **Notes:** Main lift.
        """

        let fidelity = validateFortFidelity(planText: generatedPlan, metadata: metadata)
        let codes = Set(fidelity.violations.map(\.code))
        XCTAssertTrue(codes.contains("fort_missing_anchor"))
    }

    func testValidateFortFidelityPassesWithAliasMatch() {
        let (_, metadata) = buildFortCompilerContext(dayTextMap: ["Monday": minimalSample, "Wednesday": "", "Friday": ""])
        let generatedPlan = """
        ## MONDAY
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

        let fidelity = validateFortFidelity(
            planText: generatedPlan,
            metadata: metadata,
            exerciseAliases: ["ROWERG": "Rower"]
        )
        let codes = Set(fidelity.violations.map(\.code))
        XCTAssertFalse(codes.contains("fort_missing_anchor"))
    }

    func testRepairPlanFortAnchorsInsertsMissingAnchor() {
        let (_, metadata) = buildFortCompilerContext(dayTextMap: ["Monday": minimalSample, "Wednesday": "", "Friday": ""])
        let generatedPlan = """
        ## MONDAY
        ### A1. Push Ups
        - 1 x 20 @ 0 kg
        - **Rest:** None
        - **Notes:** Bodyweight breakpoint set.
        ### B1. Back Squat
        - 4 x 8 @ 80 kg
        - **Rest:** 120 seconds
        - **Notes:** Main lift.
        """

        let (repaired, summary) = repairPlanFortAnchors(planText: generatedPlan, metadata: metadata)
        XCTAssertGreaterThanOrEqual(summary.inserted, 1)
        XCTAssertTrue(repaired.uppercased().contains("ROWERG"))

        let fidelity = validateFortFidelity(planText: repaired, metadata: metadata)
        let codes = Set(fidelity.violations.map(\.code))
        XCTAssertFalse(codes.contains("fort_missing_anchor"))
        XCTAssertTrue(codes.contains("fort_placeholder_prescription"))
    }

    func testRepairPlanFortAnchorsAddsMissingDay() {
        let (_, metadata) = buildFortCompilerContext(dayTextMap: ["Monday": minimalSample, "Wednesday": minimalSample, "Friday": ""])
        let generatedPlan = """
        ## MONDAY
        ### A1. Push Ups
        - 1 x 20 @ 0 kg
        - **Rest:** None
        - **Notes:** Bodyweight breakpoint set.
        """

        let (repaired, _) = repairPlanFortAnchors(planText: generatedPlan, metadata: metadata)
        XCTAssertTrue(repaired.contains("## WEDNESDAY"))

        let fidelity = validateFortFidelity(planText: repaired, metadata: metadata)
        let codes = Set(fidelity.violations.map(\.code))
        XCTAssertFalse(codes.contains("fort_day_missing"))
        XCTAssertFalse(codes.contains("fort_missing_anchor"))
        XCTAssertTrue(codes.contains("fort_placeholder_prescription"))
    }

    func testParseFortDayHandlesTestWeekHeadersAndNoiseFiltering() {
        let parsed = parseFortDay(dayName: "Monday", workoutText: testWeekNoiseSample)
        let sectionIDs = Set(parsed.sections.map(\.sectionID))

        XCTAssertTrue(sectionIDs.contains("prep_mobility"))
        XCTAssertTrue(sectionIDs.contains("strength_work"))
        XCTAssertTrue(sectionIDs.contains("strength_backoff"))
        XCTAssertTrue(sectionIDs.contains("conditioning"))
        XCTAssertTrue(sectionIDs.contains("auxiliary_hypertrophy"))

        let allExercises = Set(parsed.sections.flatMap(\.exercises))
        XCTAssertTrue(allExercises.contains("GARAGE - 2K BIKEERG"))
        XCTAssertFalse(allExercises.contains("TIPS"))
        XCTAssertFalse(allExercises.contains("Rest 2 minutes."))
        XCTAssertFalse(allExercises.contains("Right into..."))
    }

    func testParseFortDayStripsCompletePrefixFromSectionLine() {
        let parsed = parseFortDay(dayName: "Monday", workoutText: completeSectionPrefixSample)
        let allExercises = Set(parsed.sections.flatMap(\.exercises))
        XCTAssertTrue(allExercises.contains("GARAGE - 2K BIKEERG"))
        XCTAssertFalse(allExercises.contains("COMPLETE GARAGE - 2K BIKEERG"))
    }

    func testParseFortDayDoesNotTreatPriorityNarrativeAsSection() {
        let parsed = parseFortDay(dayName: "Monday", workoutText: prioritySample)
        let headers = Set(parsed.sections.map(\.rawHeader))
        XCTAssertFalse(headers.contains("THE PRIORITY IS THE HEAVY SINGLE (OR TRIPLE) AND THE CONDITIONING BENCHMARK. BACK OFF SETS AND AUXILIARY ARE ALL TO BE DONE TIME PERMITTING."))
    }

    func testValidateFortFidelityHandlesSplitSquatSwapAlias() {
        let (_, metadata) = buildFortCompilerContext(dayTextMap: ["Monday": "", "Wednesday": testWeekSplitSquatSample, "Friday": ""])
        let generatedPlan = """
        ## WEDNESDAY
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

        let fidelity = validateFortFidelity(
            planText: generatedPlan,
            metadata: metadata,
            exerciseAliases: ["Split Squat": "Heel-Elevated Goblet Squat"]
        )
        let codes = Set(fidelity.violations.map(\.code))
        XCTAssertFalse(codes.contains("fort_missing_anchor"))
    }

    func testValidateFortFidelityBulgarianSwapWithVariantSuffix() {
        let (_, metadata) = buildFortCompilerContext(dayTextMap: ["Monday": "", "Wednesday": "", "Friday": bulgarianSample])
        let generatedPlan = """
        ## FRIDAY
        ### G1. Heel-Elevated Goblet Squat (CONTRALATERAL)
        - 3 x 8 @ 20 kg
        - **Rest:** 90 seconds
        - **Notes:** Split squat swap rule applied.
        ### G2. 15 DEGREE DB BENCH PRESS
        - 3 x 8 @ 26 kg
        - **Rest:** 90 seconds
        - **Notes:** Upper chest.
        """

        let fidelity = validateFortFidelity(
            planText: generatedPlan,
            metadata: metadata,
            exerciseAliases: ["Bulgarian Split Squat": "Heel-Elevated Goblet Squat"]
        )
        let codes = Set(fidelity.violations.map(\.code))
        XCTAssertFalse(codes.contains("fort_missing_anchor"))
    }

    func testRepairPlanFortAnchorsRebuildsDayAndDropsNoiseRows() {
        let (_, metadata) = buildFortCompilerContext(dayTextMap: ["Monday": testWeekSample, "Wednesday": "", "Friday": ""])
        let generatedPlan = """
        ## MONDAY
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

        let (repaired, repairSummary) = repairPlanFortAnchors(planText: generatedPlan, metadata: metadata)
        XCTAssertGreaterThanOrEqual(repairSummary.dropped, 1)
        XCTAssertFalse(repaired.contains("### F1. Targeted Warm-Up"))
        XCTAssertFalse(repaired.contains("### J2. TIPS"))
        XCTAssertTrue(repaired.contains("### A1. AIR SQUAT"))
        XCTAssertTrue(repaired.contains("### F1. GARAGE - 2K BIKEERG"))
    }
}
