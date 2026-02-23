import Foundation
import GRDB
import WorkoutCore

public struct WorkoutDBSummary: Equatable, Sendable {
    public let exercises: Int
    public let sessions: Int
    public let exerciseLogs: Int
    public let logsWithRPE: Int

    public init(exercises: Int, sessions: Int, exerciseLogs: Int, logsWithRPE: Int) {
        self.exercises = exercises
        self.sessions = sessions
        self.exerciseLogs = exerciseLogs
        self.logsWithRPE = logsWithRPE
    }
}

public struct PersistedExerciseHistoryPoint: Equatable, Sendable {
    public let sessionDateISO: String
    public let load: Double
    public let reps: String
    public let notes: String

    public init(sessionDateISO: String, load: Double, reps: String, notes: String) {
        self.sessionDateISO = sessionDateISO
        self.load = load
        self.reps = reps
        self.notes = notes
    }
}

public struct PersistedWeeklySummary: Equatable, Sendable {
    public let sheetName: String
    public let sessions: Int
    public let loggedCount: Int
    public let totalCount: Int

    public init(sheetName: String, sessions: Int, loggedCount: Int, totalCount: Int) {
        self.sheetName = sheetName
        self.sessions = sessions
        self.loggedCount = loggedCount
        self.totalCount = totalCount
    }
}

public struct PersistedWeeklyVolumePoint: Equatable, Sendable {
    public let sheetName: String
    public let volume: Double

    public init(sheetName: String, volume: Double) {
        self.sheetName = sheetName
        self.volume = volume
    }
}

public struct PersistedProgressSummary: Equatable, Sendable {
    public let totalRows: Int
    public let loggedRows: Int
    public let recentLoggedRows: Int
    public let averageWeeklyVolume: Double

    public init(totalRows: Int, loggedRows: Int, recentLoggedRows: Int, averageWeeklyVolume: Double) {
        self.totalRows = totalRows
        self.loggedRows = loggedRows
        self.recentLoggedRows = recentLoggedRows
        self.averageWeeklyVolume = averageWeeklyVolume
    }
}

public struct PersistedTopExerciseSummary: Equatable, Sendable {
    public let exerciseName: String
    public let loggedCount: Int
    public let sessionCount: Int

    public init(exerciseName: String, loggedCount: Int, sessionCount: Int) {
        self.exerciseName = exerciseName
        self.loggedCount = loggedCount
        self.sessionCount = sessionCount
    }
}

public struct PersistedRecentSessionSummary: Equatable, Sendable {
    public let sheetName: String
    public let dayLabel: String
    public let sessionDateISO: String
    public let loggedRows: Int
    public let totalRows: Int

    public init(
        sheetName: String,
        dayLabel: String,
        sessionDateISO: String,
        loggedRows: Int,
        totalRows: Int
    ) {
        self.sheetName = sheetName
        self.dayLabel = dayLabel
        self.sessionDateISO = sessionDateISO
        self.loggedRows = loggedRows
        self.totalRows = totalRows
    }
}

public struct PersistedDBHealthSnapshot: Equatable, Sendable {
    public let exerciseCount: Int
    public let sessionCount: Int
    public let logCount: Int
    public let nonEmptyLogCount: Int
    public let latestSessionDateISO: String

    public init(
        exerciseCount: Int,
        sessionCount: Int,
        logCount: Int,
        nonEmptyLogCount: Int,
        latestSessionDateISO: String
    ) {
        self.exerciseCount = exerciseCount
        self.sessionCount = sessionCount
        self.logCount = logCount
        self.nonEmptyLogCount = nonEmptyLogCount
        self.latestSessionDateISO = latestSessionDateISO
    }
}

public struct PersistedWeekdayCompletion: Equatable, Sendable {
    public let dayName: String
    public let loggedRows: Int
    public let totalRows: Int

    public init(dayName: String, loggedRows: Int, totalRows: Int) {
        self.dayName = dayName
        self.loggedRows = loggedRows
        self.totalRows = totalRows
    }
}

public struct PersistedRecentLogContextRow: Equatable, Sendable {
    public let sheetName: String
    public let dayLabel: String
    public let sessionDateISO: String
    public let exerciseName: String
    public let sets: String
    public let reps: String
    public let load: String
    public let logText: String

    public init(
        sheetName: String,
        dayLabel: String,
        sessionDateISO: String,
        exerciseName: String,
        sets: String,
        reps: String,
        load: String,
        logText: String
    ) {
        self.sheetName = sheetName
        self.dayLabel = dayLabel
        self.sessionDateISO = sessionDateISO
        self.exerciseName = exerciseName
        self.sets = sets
        self.reps = reps
        self.load = load
        self.logText = logText
    }
}

public struct WorkoutSyncEntry: Equatable, Sendable {
    public let sourceRow: Int
    public let exerciseName: String
    public let block: String
    public let prescribedSets: String
    public let prescribedReps: String
    public let prescribedLoad: String
    public let prescribedRest: String
    public let prescribedNotes: String
    public let logText: String
    public let explicitRPE: String
    public let parsedNotes: String

    public init(
        sourceRow: Int,
        exerciseName: String,
        block: String,
        prescribedSets: String,
        prescribedReps: String,
        prescribedLoad: String,
        prescribedRest: String,
        prescribedNotes: String,
        logText: String,
        explicitRPE: String,
        parsedNotes: String
    ) {
        self.sourceRow = sourceRow
        self.exerciseName = exerciseName
        self.block = block
        self.prescribedSets = prescribedSets
        self.prescribedReps = prescribedReps
        self.prescribedLoad = prescribedLoad
        self.prescribedRest = prescribedRest
        self.prescribedNotes = prescribedNotes
        self.logText = logText
        self.explicitRPE = explicitRPE
        self.parsedNotes = parsedNotes
    }
}

public struct WorkoutSyncSessionInput: Equatable, Sendable {
    public let sheetName: String
    public let dayLabel: String
    public let fallbackDayName: String
    public let fallbackDateISO: String
    public let entries: [WorkoutSyncEntry]
    public let includeEmptyLogs: Bool

    public init(
        sheetName: String,
        dayLabel: String,
        fallbackDayName: String,
        fallbackDateISO: String,
        entries: [WorkoutSyncEntry],
        includeEmptyLogs: Bool = false
    ) {
        self.sheetName = sheetName
        self.dayLabel = dayLabel
        self.fallbackDayName = fallbackDayName
        self.fallbackDateISO = fallbackDateISO
        self.entries = entries
        self.includeEmptyLogs = includeEmptyLogs
    }
}

public enum WorkoutPersistenceError: Error, Equatable {
    case emptyExerciseName
}

public struct WorkoutDatabase: Sendable {
    public let dbQueue: DatabaseQueue

    public init(path: String) throws {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        if !parent.isEmpty {
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true, attributes: nil)
        }

        self.dbQueue = try DatabaseQueue(path: path)
        try dbQueue.write { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
    }

    public func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_core_schema") { db in
            try db.create(table: "exercises", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("normalized_name", .text).notNull().unique()
                t.column("created_at", .text).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("updated_at", .text).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(table: "workout_sessions", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sheet_name", .text).notNull()
                t.column("day_label", .text).notNull()
                t.column("day_name", .text)
                t.column("session_date", .text)
                t.column("source", .text).notNull().defaults(to: "google_sheets")
                t.column("created_at", .text).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("updated_at", .text).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.uniqueKey(["sheet_name", "day_label"])
            }

            try db.create(table: "exercise_logs", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_id", .integer).notNull().indexed().references("workout_sessions", onDelete: .cascade)
                t.column("exercise_id", .integer).notNull().indexed().references("exercises", onDelete: .restrict)
                t.column("block", .text)
                t.column("prescribed_sets", .text)
                t.column("prescribed_reps", .text)
                t.column("prescribed_load", .text)
                t.column("prescribed_rest", .text)
                t.column("prescribed_notes", .text)
                t.column("log_text", .text)
                t.column("parsed_rpe", .double)
                t.column("parsed_notes", .text)
                t.column("source_row", .integer).notNull()
                t.column("source", .text).notNull().defaults(to: "google_sheets")
                t.column("created_at", .text).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("updated_at", .text).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.uniqueKey(["session_id", "source_row"])
            }

            try db.create(table: "exercise_aliases", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("raw_name", .text).notNull().unique()
                t.column("canonical_key", .text).notNull().indexed()
                t.column("canonical_display", .text).notNull()
                t.column("source", .text).notNull().defaults(to: "auto")
                t.column("created_at", .text).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(index: "idx_workout_sessions_date", on: "workout_sessions", columns: ["session_date"], ifNotExists: true)
        }

        try migrator.migrate(dbQueue)
    }

    public func upsertExercise(_ exerciseName: String) throws -> Int64 {
        let normalized = getNormalizer().canonicalKey(exerciseName)
        if normalized.isEmpty {
            throw WorkoutPersistenceError.emptyExerciseName
        }

        return try dbQueue.write { db in
            let displayName = getNormalizer().canonicalName(exerciseName)
            try db.execute(
                sql: """
                INSERT INTO exercises (name, normalized_name, updated_at)
                VALUES (?, ?, datetime('now'))
                ON CONFLICT(normalized_name) DO UPDATE SET
                    name = excluded.name,
                    updated_at = datetime('now')
                """,
                arguments: [displayName, normalized]
            )

            let id = try Int64.fetchOne(db, sql: "SELECT id FROM exercises WHERE normalized_name = ?", arguments: [normalized])
            return id ?? 0
        }
    }

    public func upsertSession(sheetName: String, dayLabel: String, dayName: String, sessionDate: String?) throws -> Int64 {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO workout_sessions (sheet_name, day_label, day_name, session_date, source, updated_at)
                VALUES (?, ?, ?, ?, 'google_sheets', datetime('now'))
                ON CONFLICT(sheet_name, day_label) DO UPDATE SET
                    day_name = excluded.day_name,
                    session_date = excluded.session_date,
                    updated_at = datetime('now')
                """,
                arguments: [sheetName, dayLabel, dayName, sessionDate]
            )

            let id = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM workout_sessions WHERE sheet_name = ? AND day_label = ?",
                arguments: [sheetName, dayLabel]
            )
            return id ?? 0
        }
    }

    public func upsertExerciseLog(
        sessionID: Int64,
        exerciseID: Int64,
        entry: WorkoutSyncEntry,
        parsedRPE: Double?
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO exercise_logs (
                    session_id,
                    exercise_id,
                    block,
                    prescribed_sets,
                    prescribed_reps,
                    prescribed_load,
                    prescribed_rest,
                    prescribed_notes,
                    log_text,
                    parsed_rpe,
                    parsed_notes,
                    source_row,
                    source,
                    updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'google_sheets', datetime('now'))
                ON CONFLICT(session_id, source_row) DO UPDATE SET
                    exercise_id = excluded.exercise_id,
                    block = excluded.block,
                    prescribed_sets = excluded.prescribed_sets,
                    prescribed_reps = excluded.prescribed_reps,
                    prescribed_load = excluded.prescribed_load,
                    prescribed_rest = excluded.prescribed_rest,
                    prescribed_notes = excluded.prescribed_notes,
                    log_text = excluded.log_text,
                    parsed_rpe = excluded.parsed_rpe,
                    parsed_notes = excluded.parsed_notes,
                    updated_at = datetime('now')
                """,
                arguments: [
                    sessionID,
                    exerciseID,
                    entry.block,
                    entry.prescribedSets,
                    entry.prescribedReps,
                    entry.prescribedLoad,
                    entry.prescribedRest,
                    entry.prescribedNotes,
                    entry.logText,
                    parsedRPE,
                    entry.parsedNotes.isEmpty ? nil : entry.parsedNotes,
                    entry.sourceRow,
                ]
            )
        }
    }

    public func countSummary() throws -> WorkoutDBSummary {
        try dbQueue.read { db in
            let exercises = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exercises") ?? 0
            let sessions = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workout_sessions") ?? 0
            let logs = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exercise_logs") ?? 0
            let withRPE = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exercise_logs WHERE parsed_rpe IS NOT NULL") ?? 0
            return WorkoutDBSummary(exercises: exercises, sessions: sessions, exerciseLogs: logs, logsWithRPE: withRPE)
        }
    }

    public func fetchExerciseCatalog(limit: Int = 200) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT name
                FROM exercises
                ORDER BY LOWER(name) ASC
                LIMIT ?
                """,
                arguments: [limit]
            )
        }
    }

    public func fetchExerciseHistory(exerciseName: String, limit: Int = 24) throws -> [PersistedExerciseHistoryPoint] {
        let normalized = getNormalizer().canonicalKey(exerciseName)
        if normalized.isEmpty {
            return []
        }

        return try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    COALESCE(ws.session_date, '') AS session_date,
                    COALESCE(el.prescribed_load, '') AS prescribed_load,
                    COALESCE(el.prescribed_reps, '') AS prescribed_reps,
                    COALESCE(el.parsed_notes, '') AS parsed_notes,
                    COALESCE(el.log_text, '') AS log_text
                FROM exercise_logs el
                JOIN exercises e ON e.id = el.exercise_id
                JOIN workout_sessions ws ON ws.id = el.session_id
                WHERE e.normalized_name = ?
                ORDER BY COALESCE(ws.session_date, '') DESC, el.id DESC
                LIMIT ?
                """,
                arguments: [normalized, limit]
            )

            return rows.map { row in
                let loadText: String = row["prescribed_load"]
                let load = parseNumericScalar(loadText)
                let parsedNotes: String = row["parsed_notes"]
                let logText: String = row["log_text"]
                let notes = parsedNotes.isEmpty ? logText : parsedNotes
                return PersistedExerciseHistoryPoint(
                    sessionDateISO: row["session_date"],
                    load: load,
                    reps: row["prescribed_reps"],
                    notes: notes
                )
            }
        }
    }

    private func parseNumericScalar(_ raw: String) -> Double {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        if let value = Double(normalized) {
            return value
        }

        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#),
              let match = regex.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
              ),
              let range = Range(match.range(at: 0), in: normalized)
        else {
            return 0
        }

        return Double(normalized[range]) ?? 0
    }

    public func fetchWeeklySummaries(limit: Int = 12) throws -> [PersistedWeeklySummary] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    ws.sheet_name AS sheet_name,
                    COUNT(DISTINCT ws.id) AS sessions,
                    COALESCE(SUM(CASE WHEN TRIM(COALESCE(el.log_text, '')) <> '' THEN 1 ELSE 0 END), 0) AS logged_count,
                    COUNT(el.id) AS total_count,
                    MAX(COALESCE(ws.session_date, '')) AS max_date
                FROM workout_sessions ws
                LEFT JOIN exercise_logs el ON el.session_id = ws.id
                GROUP BY ws.sheet_name
                ORDER BY max_date DESC, ws.sheet_name DESC
                LIMIT ?
                """,
                arguments: [limit]
            )

            return rows.map { row in
                PersistedWeeklySummary(
                    sheetName: row["sheet_name"],
                    sessions: row["sessions"],
                    loggedCount: row["logged_count"],
                    totalCount: row["total_count"]
                )
            }
        }
    }

    public func fetchWeeklyVolume(limit: Int = 12) throws -> [PersistedWeeklyVolumePoint] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    ws.sheet_name AS sheet_name,
                    COALESCE(
                        SUM(
                            CASE
                                WHEN TRIM(COALESCE(el.log_text, '')) <> '' THEN
                                    COALESCE(CAST(el.prescribed_sets AS REAL), 0) *
                                    COALESCE(CAST(el.prescribed_reps AS REAL), 0) *
                                    COALESCE(CAST(el.prescribed_load AS REAL), 0)
                                ELSE 0
                            END
                        ),
                        0
                    ) AS volume,
                    MAX(COALESCE(ws.session_date, '')) AS max_date
                FROM workout_sessions ws
                LEFT JOIN exercise_logs el ON el.session_id = ws.id
                GROUP BY ws.sheet_name
                ORDER BY max_date DESC, ws.sheet_name DESC
                LIMIT ?
                """,
                arguments: [limit]
            )

            return rows.map { row in
                PersistedWeeklyVolumePoint(
                    sheetName: row["sheet_name"],
                    volume: row["volume"]
                )
            }
        }
    }

    public func fetchProgressSummary() throws -> PersistedProgressSummary {
        let weeklyVolume = try fetchWeeklyVolume(limit: 6)
        let averageVolume: Double
        if weeklyVolume.isEmpty {
            averageVolume = 0
        } else {
            let total = weeklyVolume.reduce(0.0) { partial, point in
                partial + point.volume
            }
            averageVolume = total / Double(weeklyVolume.count)
        }

        return try dbQueue.read { db in
            let totalRows = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exercise_logs") ?? 0
            let loggedRows = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exercise_logs WHERE TRIM(COALESCE(log_text, '')) <> ''") ?? 0
            let recentLoggedRows = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM exercise_logs el
                JOIN workout_sessions ws ON ws.id = el.session_id
                WHERE TRIM(COALESCE(el.log_text, '')) <> ''
                  AND COALESCE(ws.session_date, '') >= date('now', '-14 day')
                """
            ) ?? 0

            return PersistedProgressSummary(
                totalRows: totalRows,
                loggedRows: loggedRows,
                recentLoggedRows: recentLoggedRows,
                averageWeeklyVolume: averageVolume
            )
        }
    }

    public func fetchTopExerciseSummaries(limit: Int = 5) throws -> [PersistedTopExerciseSummary] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    e.name AS exercise_name,
                    SUM(CASE WHEN TRIM(COALESCE(el.log_text, '')) <> '' THEN 1 ELSE 0 END) AS logged_count,
                    COUNT(DISTINCT el.session_id) AS session_count
                FROM exercise_logs el
                JOIN exercises e ON e.id = el.exercise_id
                GROUP BY e.id
                ORDER BY logged_count DESC, session_count DESC, LOWER(e.name) ASC
                LIMIT ?
                """,
                arguments: [limit]
            )

            return rows.map { row in
                PersistedTopExerciseSummary(
                    exerciseName: row["exercise_name"],
                    loggedCount: row["logged_count"],
                    sessionCount: row["session_count"]
                )
            }
        }
    }

    public func fetchRecentSessionSummaries(limit: Int = 8) throws -> [PersistedRecentSessionSummary] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    ws.sheet_name AS sheet_name,
                    ws.day_label AS day_label,
                    COALESCE(ws.session_date, '') AS session_date,
                    SUM(CASE WHEN TRIM(COALESCE(el.log_text, '')) <> '' THEN 1 ELSE 0 END) AS logged_rows,
                    COUNT(el.id) AS total_rows
                FROM workout_sessions ws
                LEFT JOIN exercise_logs el ON el.session_id = ws.id
                GROUP BY ws.id
                ORDER BY COALESCE(ws.session_date, '') DESC, ws.id DESC
                LIMIT ?
                """,
                arguments: [limit]
            )

            return rows.map { row in
                PersistedRecentSessionSummary(
                    sheetName: row["sheet_name"],
                    dayLabel: row["day_label"],
                    sessionDateISO: row["session_date"],
                    loggedRows: row["logged_rows"],
                    totalRows: row["total_rows"]
                )
            }
        }
    }

    public func fetchDBHealthSnapshot() throws -> PersistedDBHealthSnapshot {
        try dbQueue.read { db in
            let exercises = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exercises") ?? 0
            let sessions = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workout_sessions") ?? 0
            let logs = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exercise_logs") ?? 0
            let nonEmpty = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM exercise_logs WHERE TRIM(COALESCE(log_text, '')) <> ''"
            ) ?? 0
            let latestDate = try String.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(session_date), '') FROM workout_sessions"
            ) ?? ""

            return PersistedDBHealthSnapshot(
                exerciseCount: exercises,
                sessionCount: sessions,
                logCount: logs,
                nonEmptyLogCount: nonEmpty,
                latestSessionDateISO: latestDate
            )
        }
    }

    public func fetchCompletionByWeekday() throws -> [PersistedWeekdayCompletion] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    COALESCE(ws.day_name, '') AS day_name,
                    SUM(CASE WHEN TRIM(COALESCE(el.log_text, '')) <> '' THEN 1 ELSE 0 END) AS logged_rows,
                    COUNT(el.id) AS total_rows
                FROM workout_sessions ws
                LEFT JOIN exercise_logs el ON el.session_id = ws.id
                GROUP BY ws.day_name
                ORDER BY CASE LOWER(COALESCE(ws.day_name, ''))
                    WHEN 'monday' THEN 1
                    WHEN 'tuesday' THEN 2
                    WHEN 'wednesday' THEN 3
                    WHEN 'thursday' THEN 4
                    WHEN 'friday' THEN 5
                    WHEN 'saturday' THEN 6
                    WHEN 'sunday' THEN 7
                    ELSE 99
                END ASC
                """
            )

            return rows.map { row in
                PersistedWeekdayCompletion(
                    dayName: row["day_name"],
                    loggedRows: row["logged_rows"],
                    totalRows: row["total_rows"]
                )
            }
        }
    }

    public func fetchRecentLogContextRows(limit: Int = 40) throws -> [PersistedRecentLogContextRow] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    ws.sheet_name AS sheet_name,
                    ws.day_label AS day_label,
                    COALESCE(ws.session_date, '') AS session_date,
                    e.name AS exercise_name,
                    COALESCE(el.prescribed_sets, '') AS prescribed_sets,
                    COALESCE(el.prescribed_reps, '') AS prescribed_reps,
                    COALESCE(el.prescribed_load, '') AS prescribed_load,
                    COALESCE(el.log_text, '') AS log_text
                FROM exercise_logs el
                JOIN workout_sessions ws ON ws.id = el.session_id
                JOIN exercises e ON e.id = el.exercise_id
                WHERE TRIM(COALESCE(el.log_text, '')) <> ''
                ORDER BY COALESCE(ws.session_date, '') DESC, el.id DESC
                LIMIT ?
                """,
                arguments: [limit]
            )

            return rows.map { row in
                PersistedRecentLogContextRow(
                    sheetName: row["sheet_name"],
                    dayLabel: row["day_label"],
                    sessionDateISO: row["session_date"],
                    exerciseName: row["exercise_name"],
                    sets: row["prescribed_sets"],
                    reps: row["prescribed_reps"],
                    load: row["prescribed_load"],
                    logText: row["log_text"]
                )
            }
        }
    }
}
