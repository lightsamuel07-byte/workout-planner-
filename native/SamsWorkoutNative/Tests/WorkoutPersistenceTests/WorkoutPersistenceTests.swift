import Foundation
import XCTest
import GRDB
@testable import WorkoutPersistence

final class WorkoutPersistenceTests: XCTestCase {
    private func tempDBPath(_ name: String = UUID().uuidString) -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sams-workout-tests")
            .appendingPathComponent("\(name).db")
            .path
    }

    func testBootstrapCanBeInitialized() throws {
        let path = tempDBPath("bootstrap")
        let bootstrap = PersistenceBootstrap()
        let queue = try bootstrap.openDatabase(at: path)
        let count = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='workout_sessions'")
        }
        XCTAssertEqual(count, 1)
    }

    func testWorkoutDatabaseUpsertsAndSummarizes() throws {
        let path = tempDBPath("upsert")
        let database = try WorkoutDatabase(path: path)
        try database.migrate()

        let exerciseID = try database.upsertExercise("DB Hammer Curl")
        XCTAssertGreaterThan(exerciseID, 0)

        let sessionID = try database.upsertSession(
            sheetName: "Weekly Plan (2/23/2026)",
            dayLabel: "Tuesday 2/24",
            dayName: "Tuesday",
            sessionDate: "2026-02-24"
        )
        XCTAssertGreaterThan(sessionID, 0)

        let entry = WorkoutSyncEntry(
            sourceRow: 3,
            exerciseName: "DB Hammer Curl",
            block: "B1",
            prescribedSets: "3",
            prescribedReps: "12",
            prescribedLoad: "14",
            prescribedRest: "60 seconds",
            prescribedNotes: "Strict",
            logText: "Done | RPE 8",
            explicitRPE: "",
            parsedNotes: "Good"
        )
        try database.upsertExerciseLog(sessionID: sessionID, exerciseID: exerciseID, entry: entry, parsedRPE: 8.0)

        let summary = try database.countSummary()
        XCTAssertEqual(summary.exercises, 1)
        XCTAssertEqual(summary.sessions, 1)
        XCTAssertEqual(summary.exerciseLogs, 1)
        XCTAssertEqual(summary.logsWithRPE, 1)
    }

    func testSyncServiceInfersSessionDateAndSkipsEmptyLogs() throws {
        let path = tempDBPath("sync")
        let database = try WorkoutDatabase(path: path)
        try database.migrate()
        let service = WorkoutSyncService(database: database)

        let input = WorkoutSyncSessionInput(
            sheetName: "Weekly Plan (2/23/2026)",
            dayLabel: "Tuesday 2/24",
            fallbackDayName: "Tuesday",
            fallbackDateISO: "2026-02-24",
            entries: [
                WorkoutSyncEntry(
                    sourceRow: 3,
                    exerciseName: "Reverse Pec Deck",
                    block: "B2",
                    prescribedSets: "4",
                    prescribedReps: "18",
                    prescribedLoad: "42.5",
                    prescribedRest: "60 seconds",
                    prescribedNotes: "",
                    logText: "Done, keep here | RPE 9",
                    explicitRPE: "",
                    parsedNotes: ""
                ),
                WorkoutSyncEntry(
                    sourceRow: 4,
                    exerciseName: "DB Lateral Raise",
                    block: "B3",
                    prescribedSets: "3",
                    prescribedReps: "12",
                    prescribedLoad: "8",
                    prescribedRest: "60 seconds",
                    prescribedNotes: "",
                    logText: "",
                    explicitRPE: "",
                    parsedNotes: ""
                ),
            ]
        )

        let summary = try service.sync(input: input)
        XCTAssertEqual(summary.sessions, 1)
        XCTAssertEqual(summary.exerciseLogs, 1)
        XCTAssertEqual(summary.logsWithRPE, 1)

        let storedDate = try database.dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT session_date FROM workout_sessions LIMIT 1")
        }
        XCTAssertEqual(storedDate, "2026-02-24")
    }

    func testSyncServiceCanImportEmptyLogsForFullSheetRebuild() throws {
        let path = tempDBPath("sync_include_empty")
        let database = try WorkoutDatabase(path: path)
        try database.migrate()
        let service = WorkoutSyncService(database: database)

        let input = WorkoutSyncSessionInput(
            sheetName: "Weekly Plan (2/23/2026)",
            dayLabel: "Thursday 2/26",
            fallbackDayName: "Thursday",
            fallbackDateISO: "2026-02-26",
            entries: [
                WorkoutSyncEntry(
                    sourceRow: 3,
                    exerciseName: "Reverse Pec Deck",
                    block: "B1",
                    prescribedSets: "4",
                    prescribedReps: "18",
                    prescribedLoad: "42.5",
                    prescribedRest: "60 seconds",
                    prescribedNotes: "",
                    logText: "",
                    explicitRPE: "",
                    parsedNotes: ""
                ),
            ],
            includeEmptyLogs: true
        )

        let summary = try service.sync(input: input)
        XCTAssertEqual(summary.sessions, 1)
        XCTAssertEqual(summary.exerciseLogs, 1)

        let loggedRows = try database.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exercise_logs WHERE TRIM(COALESCE(log_text, '')) <> ''")
        }
        XCTAssertEqual(loggedRows, 0)
    }

    func testSessionDateParsingSupportsDualSheetFormats() throws {
        let path = tempDBPath("dates")
        let database = try WorkoutDatabase(path: path)
        try database.migrate()
        let service = WorkoutSyncService(database: database)

        let dateA = service.inferSessionDate(
            sheetName: "Weekly Plan (2/23/2026)",
            dayLabel: "Tuesday",
            dayName: "Tuesday",
            fallbackDateISO: "2026-02-24"
        )
        let dateB = service.inferSessionDate(
            sheetName: "(Weekly Plan) 2/23/2026",
            dayLabel: "Thursday",
            dayName: "Thursday",
            fallbackDateISO: "2026-02-26"
        )

        XCTAssertEqual(dateA, "2026-02-24")
        XCTAssertEqual(dateB, "2026-02-26")
    }

    func testCoerceRPEPrefersExplicitThenLogText() throws {
        let path = tempDBPath("rpe")
        let database = try WorkoutDatabase(path: path)
        try database.migrate()
        let service = WorkoutSyncService(database: database)

        XCTAssertEqual(service.coerceRPE(explicitRPE: "8.5", logText: "RPE 9"), 8.5)
        XCTAssertEqual(service.coerceRPE(explicitRPE: "", logText: "Done | RPE 7"), 7.0)
        XCTAssertNil(service.coerceRPE(explicitRPE: "", logText: "No RPE"))
    }

    func testReadSideQueriesReturnHistoryAndWeeklyMetrics() throws {
        let path = tempDBPath("read_queries")
        let database = try WorkoutDatabase(path: path)
        try database.migrate()
        let syncService = WorkoutSyncService(database: database)

        _ = try syncService.sync(
            input: WorkoutSyncSessionInput(
                sheetName: "Weekly Plan (2/23/2026)",
                dayLabel: "Tuesday 2/24",
                fallbackDayName: "Tuesday",
                fallbackDateISO: "2026-02-24",
                entries: [
                    WorkoutSyncEntry(
                        sourceRow: 3,
                        exerciseName: "DB Hammer Curl",
                        block: "B1",
                        prescribedSets: "3",
                        prescribedReps: "12",
                        prescribedLoad: "16",
                        prescribedRest: "60 seconds",
                        prescribedNotes: "",
                        logText: "Done | RPE 8",
                        explicitRPE: "",
                        parsedNotes: "Good",
                    ),
                ]
            )
        )

        _ = try syncService.sync(
            input: WorkoutSyncSessionInput(
                sheetName: "Weekly Plan (3/2/2026)",
                dayLabel: "Tuesday 3/3",
                fallbackDayName: "Tuesday",
                fallbackDateISO: "2026-03-03",
                entries: [
                    WorkoutSyncEntry(
                        sourceRow: 3,
                        exerciseName: "DB Hammer Curl",
                        block: "B1",
                        prescribedSets: "3",
                        prescribedReps: "12",
                        prescribedLoad: "18",
                        prescribedRest: "60 seconds",
                        prescribedNotes: "",
                        logText: "Done | RPE 7.5",
                        explicitRPE: "",
                        parsedNotes: "Strong",
                    ),
                ]
            )
        )

        let history = try database.fetchExerciseHistory(exerciseName: "DB Hammer Curl")
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first?.load, 18)

        let weekly = try database.fetchWeeklySummaries(limit: 10)
        XCTAssertEqual(weekly.count, 2)
        XCTAssertTrue(weekly.contains(where: { $0.sheetName == "Weekly Plan (2/23/2026)" }))
        XCTAssertTrue(weekly.contains(where: { $0.sheetName == "Weekly Plan (3/2/2026)" }))

        let volume = try database.fetchWeeklyVolume(limit: 10)
        XCTAssertEqual(volume.count, 2)
        XCTAssertTrue(volume.allSatisfy { $0.volume > 0 })

        let progress = try database.fetchProgressSummary()
        XCTAssertEqual(progress.totalRows, 2)
        XCTAssertEqual(progress.loggedRows, 2)
        XCTAssertGreaterThan(progress.averageWeeklyVolume, 0)
    }

    func testFetchExerciseCatalogReturnsSortedNames() throws {
        let path = tempDBPath("catalog")
        let database = try WorkoutDatabase(path: path)
        try database.migrate()

        _ = try database.upsertExercise("reverse pec deck")
        _ = try database.upsertExercise("Back Squat")
        _ = try database.upsertExercise("db hammer curl")

        let catalog = try database.fetchExerciseCatalog(limit: 10)
        XCTAssertEqual(catalog, ["Back Squat", "DB Hammer Curl", "Reverse Pec Deck"])
    }
}
