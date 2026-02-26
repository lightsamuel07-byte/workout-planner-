import Foundation
import XCTest
@testable import WorkoutDesktopApp
import WorkoutIntegrations

@MainActor
final class WorkoutDesktopAppLiveE2ETests: XCTestCase {
    private func currentWeekMondayNoonUTC() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let mondayOffset = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: now) ?? now

        var components = calendar.dateComponents([.year, .month, .day], from: monday)
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: components) ?? now
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

        let gateway = LiveAppGateway(
            nowProvider: currentWeekMondayNoonUTC,
            planWriteMode: .localOnly
        )
        let status = try await gateway.generatePlan(input: liveInput())
        XCTAssertTrue(status.contains("Generated"))
        XCTAssertTrue(status.contains("local-only mode"))

        let snapshot = try await gateway.loadPlanSnapshot()
        XCTAssertFalse(snapshot.days.isEmpty)
    }

    func testLiveRebuildImportsPriorHistoryFromSheets() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_E2E"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_E2E=1 to run live integration flow.")
        }

        let gateway = LiveAppGateway()
        let report = try await gateway.rebuildDatabaseCache()

        XCTAssertGreaterThan(report.weeklySheetsScanned, 0)
        XCTAssertGreaterThan(report.daySessionsImported, 0)
        XCTAssertGreaterThan(report.exerciseRowsImported, 0)
        XCTAssertGreaterThan(report.dbExercises, 0)
        XCTAssertGreaterThan(report.dbExerciseLogs, 0)

        let knownHistory = gateway.loadExerciseHistory(exerciseName: "Reverse Pec Deck")
        XCTAssertFalse(knownHistory.isEmpty)
    }

    func testLiveWeeklySheetNamesContainNo2099Tabs() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_E2E"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_E2E=1 to run live integration flow.")
        }

        let config = FileAppConfigurationStore().load()
        XCTAssertFalse(config.spreadsheetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(config.googleAuthHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let authHint = config.googleAuthHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let token: String
        if FileManager.default.fileExists(atPath: authHint) {
            token = try await AuthSessionManager().resolveOAuthAccessToken(tokenFilePath: authHint)
        } else {
            token = authHint
        }
        let client = GoogleSheetsClient(spreadsheetID: config.spreadsheetID, authToken: token)
        let names = try await client.fetchSheetNames()

        let has2099WeeklyPlan = names.contains { name in
            name.lowercased().contains("weekly plan") && name.contains("2099")
        }
        XCTAssertFalse(has2099WeeklyPlan, "Found weekly plan tab(s) containing year 2099: \(names)")
    }
}
