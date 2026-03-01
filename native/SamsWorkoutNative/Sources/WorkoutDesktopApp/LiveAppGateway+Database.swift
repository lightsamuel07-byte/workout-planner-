import Foundation
import WorkoutIntegrations
import WorkoutPersistence

extension LiveAppGateway {
    func dbStatusText() -> String {
        let config = configStore.load()
        let base = modeStatusText(config: config)
        guard let database = try? openDatabase(),
              let summary = try? database.countSummary()
        else {
            return "\(base) | Local DB unavailable."
        }

        return "\(base) | DB: \(summary.exercises) exercises, \(summary.sessions) sessions, \(summary.exerciseLogs) logs."
    }

    func rebuildDatabaseCache() async throws -> DBRebuildReport {
        let config = try requireSheetsSetup()
        let sheetsClient = try await makeSheetsClient(config: config)
        let sheetNames = try await sheetsClient.fetchSheetNames()
        let weeklySheets = GoogleSheetsClient.allWeeklyPlanSheetsSorted(sheetNames)
        guard !weeklySheets.isEmpty else {
            throw LiveGatewayError.noWeeklyPlanSheets
        }

        // Build into a temporary DB, then swap atomically to prevent partial rebuilds.
        let dbPath = try workoutDatabasePath()
        let tempPath = dbPath + ".rebuild_tmp"
        if fileManager.fileExists(atPath: tempPath) {
            try fileManager.removeItem(atPath: tempPath)
        }

        let tempDatabase = try bootstrap.makeWorkoutDatabase(at: tempPath)
        let syncService = WorkoutSyncService(database: tempDatabase)

        var daySessionsImported = 0
        var exerciseRowsImported = 0
        var loggedRowsImported = 0

        for sheetName in weeklySheets {
            let values = try await sheetsClient.readSheetAtoH(sheetName: sheetName)
            let workouts = GoogleSheetsClient.parseDayWorkouts(values: values)
            for workout in workouts {
                let entries = workout.exercises.map { exercise -> WorkoutSyncEntry in
                    let parsed = PlanTextParser.parseExistingLog(exercise.log)
                    return WorkoutSyncEntry(
                        sourceRow: exercise.sourceRow,
                        exerciseName: exercise.exercise,
                        block: exercise.block,
                        prescribedSets: exercise.sets,
                        prescribedReps: exercise.reps,
                        prescribedLoad: exercise.load,
                        prescribedRest: exercise.rest,
                        prescribedNotes: exercise.notes,
                        logText: exercise.log,
                        explicitRPE: parsed.rpe,
                        parsedNotes: parsed.notes
                    )
                }

                guard !entries.isEmpty else {
                    continue
                }

                _ = try syncService.sync(
                    input: WorkoutSyncSessionInput(
                        sheetName: sheetName,
                        dayLabel: workout.dayLabel,
                        fallbackDayName: workout.dayName,
                        fallbackDateISO: isoDate(nowProvider()),
                        entries: entries,
                        includeEmptyLogs: true
                    )
                )

                daySessionsImported += 1
                exerciseRowsImported += entries.count
                loggedRowsImported += entries.filter {
                    !$0.logText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                }.count
            }
        }

        let summary = try tempDatabase.countSummary()

        // Preserve user-entered InBody scans before swapping — they're not in Sheets.
        let existingScans: [PersistedInBodyScan]
        if let mainDB = try? openDatabase() {
            existingScans = (try? mainDB.fetchInBodyScans()) ?? []
        } else {
            existingScans = []
        }
        for scan in existingScans {
            try? tempDatabase.upsertInBodyScan(scan)
        }

        // Atomic swap: invalidate cached DB, replace old file with completed temp DB.
        invalidateDBCache()
        if fileManager.fileExists(atPath: dbPath) {
            try fileManager.removeItem(atPath: dbPath)
        }
        try fileManager.moveItem(atPath: tempPath, toPath: dbPath)

        return DBRebuildReport(
            weeklySheetsScanned: weeklySheets.count,
            daySessionsImported: daySessionsImported,
            exerciseRowsImported: exerciseRowsImported,
            loggedRowsImported: loggedRowsImported,
            dbExercises: summary.exercises,
            dbSessions: summary.sessions,
            dbExerciseLogs: summary.exerciseLogs
        )
    }

    func openDatabase() throws -> WorkoutDatabase {
        if let existing = cachedDatabase.get() {
            return existing
        }
        let db = try bootstrap.makeWorkoutDatabase(at: workoutDatabasePath())
        cachedDatabase.set(db)
        return db
    }

    func invalidateDBCache() {
        cachedDatabase.set(nil)
    }

    func makeSyncService() throws -> WorkoutSyncService {
        WorkoutSyncService(database: try openDatabase())
    }
}
