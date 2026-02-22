import XCTest
@testable import WorkoutCore

final class ProgressionRulesParityTests: XCTestCase {
    func testBuildDirectivesMarksKeepSignalAsHoldLock() {
        let priorSupplemental: [String: [PriorSupplementalExercise]] = [
            "Tuesday": [
                PriorSupplementalExercise(
                    exercise: "Reverse Pec Deck",
                    reps: "18",
                    load: "42.5",
                    log: "Done, keep this weight and reps next week"
                ),
            ],
            "Thursday": [],
            "Saturday": [],
        ]

        let directives = buildProgressionDirectives(priorSupplemental: priorSupplemental)
        XCTAssertEqual(directives.count, 1)
        let directive = directives[0]
        XCTAssertTrue(directive.holdLock)
        XCTAssertEqual(directive.targetReps, 18)
        XCTAssertEqual(directive.targetLoad, 42.5)
    }

    func testApplyLockedDirectiveUpdatesPrescriptionLine() {
        let plan = """
        ## TUESDAY
        ### B2. Reverse Pec Deck
        - 4 x 18 @ 42 kg
        - **Rest:** 60 seconds
        - **Notes:** Hold here.
        """

        let directives = [
            ProgressionDirective(
                dayName: "tuesday",
                exerciseName: "Reverse Pec Deck",
                holdLock: true,
                targetReps: "18",
                targetLoad: 42.5
            ),
        ]

        let (updated, applied) = applyLockedDirectivesToPlan(planText: plan, directives: directives)
        XCTAssertEqual(applied, 1)
        XCTAssertTrue(updated.contains("- 4 x 18 @ 42.5 kg"))
    }
}
