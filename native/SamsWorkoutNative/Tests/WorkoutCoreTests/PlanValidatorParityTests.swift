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
}
