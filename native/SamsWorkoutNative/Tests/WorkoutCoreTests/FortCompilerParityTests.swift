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

    private let breakthroughSample = """
    MONDAY 3.02.26
    Breakthrough Season #1
    THAW:
    This week we focus on aerobic power.
    PREPARE TO ENGAGE
    CROSSOVER SYMMETRY W/Y NEGATIVE
    TERMINAL KNEE EXTENSION
    COMPLETE
    PULL UPS EVERY DAY
    PULL UP
    COMPLETE
    THE REPLACEMENTS
    SPLIT SQUAT
    COMPLETE
    THE PAY OFF
    60 DEGREE INCLINE BENCH PRESS
    OFFSET DB RDL CONTRALATERAL
    SINGLE ARM DB ROW
    COMPLETE
    THAW - AEROBIC POWER
    ROWERG
    Examples
    30 seconds at 392
    Meters
    """

    private let dynamicAliasSample = """
    MONDAY 3.09.26
    New Season #1
    SPARK ZONE
    CROSSOVER SYMMETRY W/Y NEGATIVE
    TERMINAL KNEE EXTENSION
    COMPLETE
    VERTICAL LADDER
    PULL UP
    COMPLETE
    PRIMARY DRIVER
    SPLIT SQUAT
    COMPLETE
    SUPPORT BUILDER
    SINGLE ARM DB ROW
    ZOTTMAN CURL
    COMPLETE
    ENGINE BUILDER
    ROWERG
    """

    func testFindFirstSectionIndexSkipsNarrativeLines() {
        let lines = devilDaySample.components(separatedBy: .newlines)
        let index = findFirstSectionIndex(lines: lines)
        XCTAssertNotNil(index)
        XCTAssertTrue(lines[index ?? 0].contains("IGNITION - KOT WARM-UP"))
    }

    func testFindFirstSectionIndexDetectsDynamicUnknownHeaders() {
        let lines = dynamicAliasSample.components(separatedBy: .newlines)
        let index = findFirstSectionIndex(lines: lines)
        XCTAssertNotNil(index)
        XCTAssertTrue(lines[index ?? 0].contains("SPARK ZONE"))
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

    func testParseFortDayRecognizesBreakthroughSectionsAndFiltersTableNoise() {
        let parsed = parseFortDay(dayName: "Monday", workoutText: breakthroughSample)
        let sectionIDs = Set(parsed.sections.map(\.sectionID))

        XCTAssertTrue(sectionIDs.contains("prep_mobility"))
        XCTAssertTrue(sectionIDs.contains("strength_build"))
        XCTAssertTrue(sectionIDs.contains("strength_work"))
        XCTAssertTrue(sectionIDs.contains("auxiliary_hypertrophy"))
        XCTAssertTrue(sectionIDs.contains("conditioning"))

        let allExercises = Set(parsed.sections.flatMap(\.exercises))
        XCTAssertTrue(allExercises.contains("PULL UP"))
        XCTAssertTrue(allExercises.contains("SPLIT SQUAT"))
        XCTAssertTrue(allExercises.contains("ROWERG"))
        XCTAssertFalse(allExercises.contains("PREPARE TO ENGAGE"))
        XCTAssertFalse(allExercises.contains("METERS"))
        XCTAssertFalse(allExercises.contains("EXAMPLES"))
        XCTAssertFalse(allExercises.contains("30 seconds at 392"))
    }

    func testParseFortDayInfersDynamicUnknownSectionAliases() {
        let parsed = parseFortDay(dayName: "Monday", workoutText: dynamicAliasSample)
        let sectionIDs = Set(parsed.sections.map(\.sectionID))

        XCTAssertTrue(sectionIDs.contains("prep_mobility"))
        XCTAssertTrue(sectionIDs.contains("strength_build"))
        XCTAssertTrue(sectionIDs.contains("strength_work"))
        XCTAssertTrue(sectionIDs.contains("auxiliary_hypertrophy"))
        XCTAssertTrue(sectionIDs.contains("conditioning"))

        let allExercises = Set(parsed.sections.flatMap(\.exercises))
        XCTAssertTrue(allExercises.contains("PULL UP"))
        XCTAssertTrue(allExercises.contains("SPLIT SQUAT"))
        XCTAssertTrue(allExercises.contains("ROWERG"))
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

    // Real full-fidelity Fort app text (includes intro paragraph, table noise, set numbers, percentages)
    private let breakthroughRealFortText = """
    Monday 3.02.26Breakthrough Season #1
    Prepare To Engage: A very brief mobility warm-up designed to get our joints prepared for our main strength section as well as providing some recovery from the heavy lifts we've done the past few training phases/test week.  Pull-Ups Every Day: As the name implies, we will be working on pull-ups each day of the program. On this Day One of the week we will be working on capacity and rep endurance with sets starting every minute.  The Replacements: This is our main strength work and will focus on building our squat strength while taking a break from bi-lateral back squats. Focus on full range of motion, balance and core stability here with each rep.  The Pay Off:  A giant set of auxiliary exercises that are designed to work at more challenging joint angles that will, once again, help us improve some of the typically weaker components of our main lifts. Really pay attention to rep control and tempo here. You should own every rep with the goal of maintaining perfect positions.  THAW: This week we will be focusing on Aerobic Power utilizing your test week numbers as targets for 8 minutes alternating between 30 seconds of fast and 30 seconds of slightly slower work. Sounds easier than it is.
      PREPARE TO ENGAGE
    1 Set
    1
    CROSSOVER SYMMETRY W/Y NEGATIVE
    TIPS HISTORY
    Reps
    TERMINAL KNEE EXTENSION
    HISTORY
    Number of reps is per side
    Reps
    COMPLETE
      PULL UPS EVERY DAY
    PULL UP
    TIPS HISTORY
    Perform as an EMOM doing 4-8 reps per set. The only people doing 8 reps are those who can do them bodyweight. Otherwise use the lightest band possible that allows you to get at least 4 reps (prioritize less assistance even if that means less reps)
    3 Sets
    Reps
    1
    2
    3
    COMPLETE
      THE REPLACEMENTS
    SPLIT SQUAT
    TIPS HISTORY
    Barbell back racked split squats. Number of reps is per side. Complete all reps on one side prior to switching. Weight guidance is based on Back Squat 1RM
    3 Sets
    Reps
    Weight
    1
    40%
    2
    40%
    3
    40%
    COMPLETE
      THE PAY OFF
    Perform one set every 4 minutes
    3 Sets
    1
    2
    3
    60 DEGREE INCLINE BENCH PRESS
    HISTORY
    Set Bench at 60 degrees. Take a brief pause at the chest (eliminate the bounce)
    Reps
    Weight
    OFFSET DB RDL CONTRALATERAL
    TIPS HISTORY
    Controlled eccentric tempo, 1 second pause at the stretch. Number of reps is per side.
    Reps
    Weight
    SINGLE ARM DB ROW
    TIPS HISTORY
    Controlled eccentric tempo, 1 second pause at the stretch. Number of reps is per side.
    Reps
    Weight
    COMPLETE
      THAW -  AEROBIC POWER
    ROWERG
    TIPS HISTORY
    8 rounds of 30 seconds at 0-5 seconds slower than your 2k pace, 30 seconds at 15-20 seconds slower than your 2k pace. Track your overall 500m pace and your individual paces on each of the faster 8 efforts. If you can accumulate over 2k meters here you are doing well.
    8 Sets
    Time (mm:ss)
    Other Number
    1
    2
    3
    4
    5
    6
    7
    8
    Meters
    Rx
    """

    // When the Fort narrative intro contains "THAW:" as a standalone ALL-CAPS label
    // before the structured section tables, the compiler must not emit an empty
    // conditioning section (it would appear at the top of the preview with "?").
    func testParseFortDayFiltersPhantomEmptySectionsFromNarrativeLabels() {
        let textWithNarrativeThaw = """
        Monday 3.02.26Breakthrough Season #1
        PREPARE TO ENGAGE: warmup description here.
        THAW:
        PREPARE TO ENGAGE
        CROSSOVER SYMMETRY W/Y NEGATIVE
        TERMINAL KNEE EXTENSION
        THAW - AEROBIC POWER
        ROWERG
        """
        let parsed = parseFortDay(dayName: "Monday", workoutText: textWithNarrativeThaw)
        // The narrative "THAW:" line has no exercises — it must be filtered out.
        // The real "THAW - AEROBIC POWER" section has ROWERG and must be present.
        let emptySections = parsed.sections.filter { $0.exercises.isEmpty }
        XCTAssertTrue(emptySections.isEmpty,
            "Phantom empty sections must be filtered; found: \(emptySections.map(\.rawHeader))")
        // Conditioning section must exist (from the real THAW - AEROBIC POWER line)
        let conditioningSection = parsed.sections.first(where: { $0.sectionID == "conditioning" })
        XCTAssertNotNil(conditioningSection, "Real conditioning section must be present")
        XCTAssertFalse(conditioningSection?.exercises.isEmpty ?? true,
            "Real conditioning section must have exercises")
        // prep_mobility block letter must be A (not shifted by phantom rank-6 section)
        let prepCompiled = parsed.compiledSections.first(where: { $0.sectionID == "prep_mobility" })
        XCTAssertEqual(prepCompiled?.blockLetter, "A",
            "prep_mobility must be block A; phantom THAW must not push rank to F")
    }

    func testParseFortDayRealBreakthroughTextExtractsAllSections() {
        let parsed = parseFortDay(dayName: "Monday", workoutText: breakthroughRealFortText)
        let sectionIDs = Set(parsed.sections.map(\.sectionID))
        let allExercises = Set(parsed.sections.flatMap(\.exercises))

        // All five section types must be present
        XCTAssertTrue(sectionIDs.contains("prep_mobility"), "Missing prep_mobility (PREPARE TO ENGAGE)")
        XCTAssertTrue(sectionIDs.contains("strength_build"), "Missing strength_build (PULL UPS EVERY DAY)")
        XCTAssertTrue(sectionIDs.contains("strength_work"), "Missing strength_work (THE REPLACEMENTS)")
        XCTAssertTrue(sectionIDs.contains("auxiliary_hypertrophy"), "Missing auxiliary_hypertrophy (THE PAY OFF)")
        XCTAssertTrue(sectionIDs.contains("conditioning"), "Missing conditioning (THAW)")

        // Core exercises must be extracted
        XCTAssertTrue(allExercises.contains("CROSSOVER SYMMETRY W/Y NEGATIVE"), "Missing CROSSOVER SYMMETRY")
        XCTAssertTrue(allExercises.contains("TERMINAL KNEE EXTENSION"), "Missing TERMINAL KNEE EXTENSION")
        XCTAssertTrue(allExercises.contains("PULL UP"), "Missing PULL UP")
        XCTAssertTrue(allExercises.contains("SPLIT SQUAT"), "Missing SPLIT SQUAT (main lift)")
        XCTAssertTrue(allExercises.contains("60 DEGREE INCLINE BENCH PRESS"), "Missing INCLINE BENCH PRESS")
        XCTAssertTrue(allExercises.contains("OFFSET DB RDL CONTRALATERAL"), "Missing OFFSET DB RDL")
        XCTAssertTrue(allExercises.contains("SINGLE ARM DB ROW"), "Missing SINGLE ARM DB ROW")
        XCTAssertTrue(allExercises.contains("ROWERG"), "Missing ROWERG")

        // Section headers / noise must NOT appear as exercises
        XCTAssertFalse(allExercises.contains("PREPARE TO ENGAGE"), "Section header leaked as exercise")
        XCTAssertFalse(allExercises.contains("PULL UPS EVERY DAY"), "Section header leaked as exercise")
        XCTAssertFalse(allExercises.contains("THE REPLACEMENTS"), "Section header leaked as exercise")
        XCTAssertFalse(allExercises.contains("THE PAY OFF"), "Section header leaked as exercise")
        XCTAssertFalse(allExercises.contains("METERS"), "Table header leaked as exercise")
        XCTAssertFalse(allExercises.contains("Meters"), "Table header leaked as exercise")

        // Compiled sections should have correct block letters (A, B, C, E, F — not F, G)
        let compiled = parsed.compiledSections
        let prepSection = compiled.first(where: { $0.sectionID == "prep_mobility" })
        let strengthSection = compiled.first(where: { $0.sectionID == "strength_work" })
        XCTAssertNotNil(prepSection, "No compiled prep_mobility section")
        XCTAssertNotNil(strengthSection, "No compiled strength_work section")
        XCTAssertEqual(prepSection?.blockLetter, "A", "prep_mobility should be block A, got \(prepSection?.blockLetter ?? "nil")")
        XCTAssertEqual(strengthSection?.blockLetter, "C", "strength_work should be block C, got \(strengthSection?.blockLetter ?? "nil")")
    }
}
