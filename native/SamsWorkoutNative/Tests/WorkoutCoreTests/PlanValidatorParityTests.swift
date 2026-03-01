import XCTest
@testable import WorkoutCore

final class PlanValidatorParityTests: XCTestCase {
    private func violationCodes(_ result: PlanValidationResult) -> Set<String> {
        Set(result.violations.map(\.code))
    }

    func testDetectsOddDumbbellLoadViolation() {
        let plan = """
        ## TUESDAY
        ### B1. DB Lateral Raise
        - 4 x 12 @ 7 kg
        - **Rest:** 60 seconds
        - **Notes:** Strict form.
        """

        let result = validatePlan(plan)
        XCTAssertTrue(violationCodes(result).contains("odd_db_load"))
    }

    func testDetectsHoldLockViolation() {
        let plan = """
        ## THURSDAY
        ### D1. Hammer Curl (Neutral Grip)
        - 3 x 10 @ 16 kg
        - **Rest:** 60 seconds
        - **Notes:** Hold until form improves.
        """

        let directives = [
            ProgressionDirective(
                dayName: "thursday",
                exerciseName: "Hammer Curl (Neutral Grip)",
                holdLock: true,
                targetReps: "12",
                targetLoad: 16.0
            ),
        ]

        let result = validatePlan(plan, progressionDirectives: directives)
        XCTAssertTrue(violationCodes(result).contains("hold_lock_violation"))
    }

    func testDetectsOddDBSquatLoadViolation() {
        let plan = """
        ## WEDNESDAY
        ### E1. Low-Hold DB Goblet Squat
        - 3 x 8 @ 29 kg
        - **Rest:** 90 seconds
        - **Notes:** Control tempo.
        """

        let result = validatePlan(plan)
        XCTAssertTrue(violationCodes(result).contains("odd_db_load"))
    }

    func testDoesNotFlagBicepsRotationWhenNotesMentionOtherDays() {
        let plan = """
        ## TUESDAY
        ### D1. Incline DB Curl (Supinated)
        - 3 x 12 @ 14 kg
        - **Rest:** 60 seconds
        - **Notes:** Supinated grip. Long-length stimulus.
        ## THURSDAY
        ### D1. Cable Curl (Straight Bar, Pronated Grip)
        - 3 x 10 @ 27 kg
        - **Rest:** 60 seconds
        - **Notes:** Pronated grip to avoid repeat (Tue supinated -> Thu pronated -> Sat neutral).
        ## SATURDAY
        ### D1. Hammer Curl (Neutral Grip)
        - 3 x 15 @ 14 kg
        - **Rest:** 60 seconds
        - **Notes:** Neutral grip to complete rotation (Tue supinated -> Thu pronated -> Sat neutral).
        """

        let result = validatePlan(plan)
        XCTAssertFalse(violationCodes(result).contains("biceps_grip_repeat"))
    }

    func testDetectsUnderfilledSupplementalDay() {
        let plan = """
        ## TUESDAY
        ### D1. Incline DB Curl (Supinated)
        - 3 x 12 @ 14 kg
        - **Rest:** 60 seconds
        - **Notes:** Supinated grip.
        ### D2. Rope Pressdown
        - 3 x 12 @ 22 kg
        - **Rest:** 60 seconds
        - **Notes:** Triceps.
        ### D3. Face Pull
        - 3 x 15 @ 18 kg
        - **Rest:** 60 seconds
        - **Notes:** Upper back.
        ## THURSDAY
        ### D1. Cable Curl (Pronated Grip)
        - 3 x 10 @ 20 kg
        - **Rest:** 60 seconds
        - **Notes:** Pronated grip.
        ### D2. Floor Press
        - 3 x 10 @ 24 kg
        - **Rest:** 90 seconds
        - **Notes:** Control.
        ### D3. Rear Delt Raise
        - 3 x 15 @ 8 kg
        - **Rest:** 60 seconds
        - **Notes:** Tempo.
        ## SATURDAY
        ### D1. Triceps Pushdown (V-Bar)
        - 3 x 12 @ 22 kg
        - **Rest:** 60 seconds
        - **Notes:** Single exercise day.
        """

        let result = validatePlan(plan)
        XCTAssertTrue(violationCodes(result).contains("supplemental_day_underfilled"))
    }

    func testDetectsLowerBodyExerciseOnSupplementalDay() {
        let plan = """
        ## THURSDAY
        ### D1. Barbell RDL
        - 3 x 10 @ 80 kg
        - **Rest:** 90 seconds
        - **Notes:** Hip hinge pattern.
        ### D2. KB Swing
        - 3 x 15 @ 24 kg
        - **Rest:** 60 seconds
        - **Notes:** Explosive hinge.
        """

        let result = validatePlan(plan)
        XCTAssertTrue(violationCodes(result).contains("lower_body_on_supplemental"),
            "RDL and KB Swing on Thursday should trigger lower_body_on_supplemental")
    }

    func testDoesNotFlagLowerBodyOnFortDay() {
        let plan = """
        ## MONDAY
        ### A1. Back Squat
        - 4 x 5 @ 110 kg
        - **Rest:** 3 min
        - **Notes:** Brace hard.
        ## WEDNESDAY
        ### A1. Romanian Deadlift
        - 3 x 8 @ 100 kg
        - **Rest:** 2 min
        - **Notes:** Slow eccentric.
        """

        let result = validatePlan(plan)
        XCTAssertFalse(violationCodes(result).contains("lower_body_on_supplemental"),
            "Squats and RDLs on Fort days (Mon/Wed) must not be flagged")
    }

    func testDetectsFortHeaderAsExerciseNoise() {
        let plan = """
        ## MONDAY
        ### F1. PREPARE TO ENGAGE
        - 1 x 60 @ 0 kg
        - **Rest:** None
        - **Notes:** Header leaked into exercise list.
        ### F2. Meters
        - 1 x 60 @ 0 kg
        - **Rest:** None
        - **Notes:** Table label leaked into exercise list.
        """

        let result = validatePlan(plan)
        XCTAssertTrue(violationCodes(result).contains("fort_header_as_exercise"))
    }
}
