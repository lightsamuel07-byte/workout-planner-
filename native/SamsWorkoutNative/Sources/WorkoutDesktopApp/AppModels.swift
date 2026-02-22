import Foundation

enum AppRoute: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case generatePlan = "Generate Plan"
    case viewPlan = "View Plan"
    case logWorkout = "Log Workout"
    case progress = "Progress"
    case weeklyReview = "Weekly Review"
    case exerciseHistory = "Exercise History"
    case dbStatus = "DB Status"

    var id: String { rawValue }
}

enum DataSourceLabel: String {
    case googleSheets = "Google Sheets"
    case localCache = "Local DB Cache"
}

struct SetupState: Equatable {
    var anthropicAPIKey: String = ""
    var spreadsheetID: String = ""
    var googleAuthHint: String = "OAuth token path"
    var localAppPassword: String = ""

    func validate() -> [String] {
        var errors: [String] = []
        if anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Anthropic API key is required.")
        }
        if spreadsheetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Google Spreadsheet ID is required.")
        }
        return errors
    }
}

struct PlanGenerationInput: Equatable {
    var monday: String = ""
    var wednesday: String = ""
    var friday: String = ""

    var canGenerate: Bool {
        !monday.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !wednesday.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !friday.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DayPlanSummary: Equatable, Identifiable {
    let id: String
    let title: String
    let source: DataSourceLabel
    let blocks: Int
}

struct ExerciseHistoryPoint: Equatable, Identifiable {
    let id: UUID
    let dateISO: String
    let load: Double
    let reps: String
    let notes: String
}

struct PlanExerciseRow: Equatable, Identifiable {
    let id: UUID
    let sourceRow: Int?
    let block: String
    let exercise: String
    let sets: String
    let reps: String
    let load: String
    let rest: String
    let notes: String
    let log: String

    init(
        id: UUID = UUID(),
        sourceRow: Int?,
        block: String,
        exercise: String,
        sets: String,
        reps: String,
        load: String,
        rest: String,
        notes: String,
        log: String
    ) {
        self.id = id
        self.sourceRow = sourceRow
        self.block = block
        self.exercise = exercise
        self.sets = sets
        self.reps = reps
        self.load = load
        self.rest = rest
        self.notes = notes
        self.log = log
    }
}

struct PlanDayDetail: Equatable, Identifiable {
    let id: String
    let dayLabel: String
    let source: DataSourceLabel
    let exercises: [PlanExerciseRow]
}

struct PlanSnapshot: Equatable {
    let title: String
    let source: DataSourceLabel
    let days: [PlanDayDetail]
    let summary: String

    static let empty = PlanSnapshot(
        title: "",
        source: .localCache,
        days: [],
        summary: ""
    )
}

struct WorkoutLogDraft: Equatable, Identifiable {
    let id: UUID
    let sourceRow: Int
    let block: String
    let exercise: String
    let sets: String
    let reps: String
    let load: String
    let rest: String
    let notes: String
    var existingLog: String
    var performance: String
    var rpe: String
    var noteEntry: String

    init(
        id: UUID = UUID(),
        sourceRow: Int,
        block: String,
        exercise: String,
        sets: String,
        reps: String,
        load: String,
        rest: String,
        notes: String,
        existingLog: String,
        performance: String = "",
        rpe: String = "",
        noteEntry: String = ""
    ) {
        self.id = id
        self.sourceRow = sourceRow
        self.block = block
        self.exercise = exercise
        self.sets = sets
        self.reps = reps
        self.load = load
        self.rest = rest
        self.notes = notes
        self.existingLog = existingLog
        self.performance = performance
        self.rpe = rpe
        self.noteEntry = noteEntry
    }
}

struct LoggerSessionState: Equatable {
    var sheetName: String
    var dayLabel: String
    var source: DataSourceLabel
    var drafts: [WorkoutLogDraft]

    static let empty = LoggerSessionState(
        sheetName: "",
        dayLabel: "",
        source: .googleSheets,
        drafts: []
    )
}

struct ProgressSummary: Equatable {
    var completionRateText: String
    var weeklyVolumeText: String
    var recentLoggedText: String
    var sourceText: String

    static let empty = ProgressSummary(
        completionRateText: "Completion rate: n/a",
        weeklyVolumeText: "Weekly volume: n/a",
        recentLoggedText: "Recent logs: 0",
        sourceText: "Source: Local DB cache"
    )
}

struct WeeklyReviewSummary: Equatable, Identifiable {
    let id: UUID
    let sheetName: String
    let sessions: Int
    let loggedCount: Int
    let totalCount: Int
    let completionRateText: String

    init(
        id: UUID = UUID(),
        sheetName: String,
        sessions: Int,
        loggedCount: Int,
        totalCount: Int,
        completionRateText: String
    ) {
        self.id = id
        self.sheetName = sheetName
        self.sessions = sessions
        self.loggedCount = loggedCount
        self.totalCount = totalCount
        self.completionRateText = completionRateText
    }
}

struct DBRebuildReport: Equatable {
    let weeklySheetsScanned: Int
    let daySessionsImported: Int
    let exerciseRowsImported: Int
    let loggedRowsImported: Int
    let dbExercises: Int
    let dbSessions: Int
    let dbExerciseLogs: Int
}
