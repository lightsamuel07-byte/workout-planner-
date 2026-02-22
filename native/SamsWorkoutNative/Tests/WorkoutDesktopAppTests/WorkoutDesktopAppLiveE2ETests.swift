import Foundation
import XCTest
@testable import WorkoutDesktopApp

@MainActor
final class WorkoutDesktopAppLiveE2ETests: XCTestCase {
    private func fixedNow() -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2099
        components.month = 1
        components.day = 6
        components.hour = 12
        components.minute = 0
        components.second = 0
        return components.date ?? Date()
    }

    private func liveInput() -> PlanGenerationInput {
        PlanGenerationInput(
            monday: """
            MONDAY
            IGNITION
            Deadbug
            CLUSTER SET
            Back Squat
            AUXILIARY
            Reverse Pec Deck
            THAW
            BikeErg
            """,
            wednesday: """
            WEDNESDAY
            PREP
            Hip Airplane
            WORKING SET
            Bench Press
            AUXILIARY
            Rope Pressdown
            THAW
            Incline Walk
            """,
            friday: """
            FRIDAY
            IGNITION
            McGill Big-3
            BREAKPOINT
            Deadlift
            AUXILIARY
            DB Hammer Curl
            THAW
            Rower
            """
        )
    }

    func testLiveGenerateWriteLogAndSync() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_E2E"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_E2E=1 to run live integration flow.")
        }

        let gateway = LiveAppGateway(nowProvider: fixedNow)
        let status = try await gateway.generatePlan(input: liveInput())
        XCTAssertTrue(status.contains("Generated"))

        let snapshot = try await gateway.loadPlanSnapshot()
        XCTAssertFalse(snapshot.days.isEmpty)

        var session = try await gateway.loadTodayLoggerSession()
        guard !session.drafts.isEmpty else {
            XCTFail("Logger returned no draft exercises after generation.")
            return
        }

        session.drafts[0].performance = "Done"
        session.drafts[0].rpe = "8"
        session.drafts[0].noteEntry = "live-e2e-2099"

        let dbSummary = try await gateway.saveLoggerSession(session)
        XCTAssertGreaterThan(dbSummary.exerciseLogs, 0)

        let refreshed = try await gateway.loadTodayLoggerSession()
        let existing = refreshed.drafts.first?.existingLog ?? ""
        XCTAssertTrue(existing.contains("live-e2e-2099") || existing.contains("Done"))
    }

    func testLiveRebuildImportsPriorHistoryFromSheets() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_E2E"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_E2E=1 to run live integration flow.")
        }

        let gateway = LiveAppGateway(nowProvider: fixedNow)
        let report = try await gateway.rebuildDatabaseCache()

        XCTAssertGreaterThan(report.weeklySheetsScanned, 0)
        XCTAssertGreaterThan(report.daySessionsImported, 0)
        XCTAssertGreaterThan(report.exerciseRowsImported, 0)
        XCTAssertGreaterThan(report.dbExercises, 0)
        XCTAssertGreaterThan(report.dbExerciseLogs, 0)

        let knownHistory = gateway.loadExerciseHistory(exerciseName: "Reverse Pec Deck")
        XCTAssertFalse(knownHistory.isEmpty)
    }
}
