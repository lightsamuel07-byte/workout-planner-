import Foundation
import XCTest
@testable import WorkoutDesktopApp
import WorkoutIntegrations
import WorkoutPersistence

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

    private func normalizeLog(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func preferredLiveSheetName(
        gateway: LiveAppGateway,
        sheetsClient: GoogleSheetsClient
    ) async throws -> String {
        let names = try await sheetsClient.fetchSheetNames()
        if let preferred = LiveAppGateway.testPreferredWeeklyPlanSheetName(names, referenceDate: Date()) {
            return preferred
        }
        if let mostRecent = GoogleSheetsClient.mostRecentWeeklyPlanSheet(names) {
            return mostRecent
        }
        throw XCTSkip("No weekly plan sheets available for live conflict E2E.")
    }

    private func makeSyncEntry(exercise: SheetDayExercise, log: String) -> WorkoutSyncEntry {
        let parsed = PlanTextParser.parseExistingLog(log)
        return WorkoutSyncEntry(
            sourceRow: exercise.sourceRow,
            exerciseName: exercise.exercise,
            block: exercise.block,
            prescribedSets: exercise.sets,
            prescribedReps: exercise.reps,
            prescribedLoad: exercise.load,
            prescribedRest: exercise.rest,
            prescribedNotes: exercise.notes,
            logText: log,
            explicitRPE: parsed.rpe,
            parsedNotes: parsed.notes
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

    func testLiveBidirectionalConflictSyncWritesAuditForDivergedRow() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_E2E"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_E2E=1 to run live integration flow.")
        }

        let configStore = FileAppConfigurationStore()
        let originalConfig = configStore.load()
        var testConfig = originalConfig
        testConfig.bidirectionalSyncConflictPolicy = .preferDatabase
        try configStore.save(testConfig)
        defer { try? configStore.save(originalConfig) }

        let gateway = LiveAppGateway()
        let config = try gateway.requireSheetsSetup()
        let sheetsClient = try await gateway.makeSheetsClient(config: config)
        let sheetName = try await preferredLiveSheetName(gateway: gateway, sheetsClient: sheetsClient)

        _ = try await gateway.rebuildDatabaseCache()

        let values = try await sheetsClient.readSheetAtoH(sheetName: sheetName)
        let workouts = GoogleSheetsClient.parseDayWorkouts(values: values)
        guard let targetWorkout = workouts.first(where: { !$0.exercises.isEmpty }),
              let targetExercise = targetWorkout.exercises.first(where: {
                  !$0.exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw XCTSkip("No parseable exercise rows available for live conflict E2E.")
        }

        let originalLog = normalizeLog(targetExercise.log)
        let uniqueMarker = UUID().uuidString.prefix(8)
        let sheetConflictLog = "sheet conflict \(uniqueMarker) | RPE 7 | Notes: live-e2e"
        let dbConflictLog = "db conflict \(uniqueMarker) | RPE 9 | Notes: live-e2e"

        let database = try gateway.openDatabase()
        let syncService = try gateway.makeSyncService()
        let existingAuditMaxID = try database.fetchRecentSyncAuditEvents(limit: 500).map(\.id).max() ?? 0

        try database.upsertLogSyncState(
            PersistedLogSyncState(
                sheetName: sheetName,
                dayLabel: targetWorkout.dayLabel,
                sourceRow: targetExercise.sourceRow,
                lastSyncedSheetLog: originalLog,
                lastSyncedDBLog: originalLog,
                lastResolution: "unchanged"
            )
        )

        let restoreEntry = makeSyncEntry(exercise: targetExercise, log: originalLog)
        let conflictEntry = makeSyncEntry(exercise: targetExercise, log: dbConflictLog)

        var needsRestore = false
        do {
            try await sheetsClient.batchUpdateLogs([
                ValueRangeUpdate(
                    range: "'\(sheetName)'!H\(targetExercise.sourceRow)",
                    values: [[sheetConflictLog]]
                )
            ])
            needsRestore = true

            _ = try syncService.sync(
                input: WorkoutSyncSessionInput(
                    sheetName: sheetName,
                    dayLabel: targetWorkout.dayLabel,
                    fallbackDayName: targetWorkout.dayName,
                    fallbackDateISO: gateway.isoDate(gateway.nowProvider()),
                    entries: [conflictEntry],
                    includeEmptyLogs: true
                )
            )

            _ = try await gateway.loadPlanSnapshot(forceRemote: true)

            let refreshedValues = try await sheetsClient.readSheetAtoH(sheetName: sheetName)
            let refreshedSheetLog = normalizeLog(
                refreshedValues[targetExercise.sourceRow - 1][7]
            )
            XCTAssertEqual(refreshedSheetLog, dbConflictLog)

            let refreshedDBRow = try database
                .fetchSessionLogRows(sheetName: sheetName, dayLabel: targetWorkout.dayLabel)
                .first { $0.sourceRow == targetExercise.sourceRow }
            XCTAssertEqual(normalizeLog(refreshedDBRow?.logText ?? ""), dbConflictLog)

            let summary = gateway.latestBidirectionalSyncSummary()
            XCTAssertTrue(summary.contains("conflicts 1"), "Unexpected live sync summary: \(summary)")
            XCTAssertTrue(summary.contains("policy prefer_database"), "Unexpected live sync summary: \(summary)")

            let recentAudit = try database.fetchRecentSyncAuditEvents(limit: 500)
            let matchingAudit = recentAudit.first {
                $0.id > existingAuditMaxID &&
                $0.sheetName == sheetName &&
                $0.dayLabel == targetWorkout.dayLabel &&
                $0.sourceRow == targetExercise.sourceRow &&
                normalizeLog($0.resolvedLog) == dbConflictLog
            }

            XCTAssertNotNil(matchingAudit)
            XCTAssertEqual(matchingAudit?.resolution, "conflict_resolved_to_db")
            XCTAssertEqual(matchingAudit?.countsAsConflict, true)
            XCTAssertEqual(matchingAudit?.didPushToSheets, true)
            XCTAssertEqual(matchingAudit?.didPullToDB, false)
        } catch {
            if needsRestore {
                try? await sheetsClient.batchUpdateLogs([
                    ValueRangeUpdate(
                        range: "'\(sheetName)'!H\(targetExercise.sourceRow)",
                        values: [[originalLog]]
                    )
                ])
                _ = try? syncService.sync(
                    input: WorkoutSyncSessionInput(
                        sheetName: sheetName,
                        dayLabel: targetWorkout.dayLabel,
                        fallbackDayName: targetWorkout.dayName,
                        fallbackDateISO: gateway.isoDate(gateway.nowProvider()),
                        entries: [restoreEntry],
                        includeEmptyLogs: true
                    )
                )
                try? database.upsertLogSyncState(
                    PersistedLogSyncState(
                        sheetName: sheetName,
                        dayLabel: targetWorkout.dayLabel,
                        sourceRow: targetExercise.sourceRow,
                        lastSyncedSheetLog: originalLog,
                        lastSyncedDBLog: originalLog,
                        lastResolution: "test_restore"
                    )
                )
            }
            throw error
        }

        if needsRestore {
            try await sheetsClient.batchUpdateLogs([
                ValueRangeUpdate(
                    range: "'\(sheetName)'!H\(targetExercise.sourceRow)",
                    values: [[originalLog]]
                )
            ])
            _ = try syncService.sync(
                input: WorkoutSyncSessionInput(
                    sheetName: sheetName,
                    dayLabel: targetWorkout.dayLabel,
                    fallbackDayName: targetWorkout.dayName,
                    fallbackDateISO: gateway.isoDate(gateway.nowProvider()),
                    entries: [restoreEntry],
                    includeEmptyLogs: true
                )
            )
            try database.upsertLogSyncState(
                PersistedLogSyncState(
                    sheetName: sheetName,
                    dayLabel: targetWorkout.dayLabel,
                    sourceRow: targetExercise.sourceRow,
                    lastSyncedSheetLog: originalLog,
                    lastSyncedDBLog: originalLog,
                    lastResolution: "test_restore"
                )
            )
        }
    }
}
