import Foundation

enum AppRoute: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case generatePlan = "Generate Plan"
    case viewPlan = "View Plan"
    case progress = "Progress"
    case weeklyReview = "Weekly Review"
    case exerciseHistory = "Exercise History"
    case settings = "Settings"

    var id: String { rawValue }
}

enum DataSourceLabel: String {
    case googleSheets = "Google Sheets"
    case localCache = "Local DB Cache"
}

enum StatusSeverity: String, Equatable {
    case info
    case success
    case warning
    case error
}

struct StatusBanner: Equatable {
    let text: String
    let severity: StatusSeverity

    static let empty = StatusBanner(text: "", severity: .info)
}

struct SetupState: Equatable {
    var anthropicAPIKey: String = ""
    var spreadsheetID: String = ""
    var googleAuthHint: String = "OAuth token path"

    func validate() -> [String] {
        var errors: [String] = []
        if anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Anthropic API key is required.")
        }
        let trimmedSheet = spreadsheetID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSheet.isEmpty {
            errors.append("Google Spreadsheet ID is required.")
        } else if trimmedSheet.range(of: #"^[A-Za-z0-9_-]{20,}$"#, options: .regularExpression) == nil {
            errors.append("Google Spreadsheet ID format looks invalid. Expected a long alphanumeric string from the Sheets URL.")
        }
        return errors
    }
}

struct SetupChecklistItem: Equatable, Identifiable {
    let id: String
    let title: String
    let isComplete: Bool
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

struct GenerationReadinessReport: Equatable {
    let missingDays: [String]
    let missingHeaders: [String]
    let lowSignalDays: [String]
    let duplicatedDayPairs: [String]

    var issues: [String] {
        var rows: [String] = []
        if !missingDays.isEmpty {
            rows.append("Missing day input: \(missingDays.joined(separator: ", ")).")
        }
        if !missingHeaders.isEmpty {
            rows.append("Missing explicit day header in: \(missingHeaders.joined(separator: ", ")).")
        }
        if !lowSignalDays.isEmpty {
            rows.append("Too little signal (<3 non-empty lines): \(lowSignalDays.joined(separator: ", ")).")
        }
        rows.append(contentsOf: duplicatedDayPairs)
        return rows
    }

    var isReady: Bool {
        issues.isEmpty
    }

    var summary: String {
        if isReady {
            return "Readiness checks passed."
        }
        return issues.joined(separator: " ")
    }

    static let empty = GenerationReadinessReport(
        missingDays: [],
        missingHeaders: [],
        lowSignalDays: [],
        duplicatedDayPairs: []
    )
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

struct WeeklyVolumePoint: Equatable, Identifiable {
    let id: UUID
    let sheetName: String
    let volume: Double

    init(id: UUID = UUID(), sheetName: String, volume: Double) {
        self.id = id
        self.sheetName = sheetName
        self.volume = volume
    }
}

struct WeeklyRPEPoint: Equatable, Identifiable {
    let id: UUID
    let sheetName: String
    let averageRPE: Double
    let rpeCount: Int

    init(id: UUID = UUID(), sheetName: String, averageRPE: Double, rpeCount: Int) {
        self.id = id
        self.sheetName = sheetName
        self.averageRPE = averageRPE
        self.rpeCount = rpeCount
    }
}

struct MuscleGroupVolume: Equatable, Identifiable {
    let id: UUID
    let muscleGroup: String
    let volume: Double
    let exerciseCount: Int

    init(id: UUID = UUID(), muscleGroup: String, volume: Double, exerciseCount: Int) {
        self.id = id
        self.muscleGroup = muscleGroup
        self.volume = volume
        self.exerciseCount = exerciseCount
    }
}

enum WeeklyReviewSortMode: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case highestCompletion = "Highest Completion"
    case lowestCompletion = "Lowest Completion"
    case mostSessions = "Most Sessions"

    var id: String { rawValue }
}

struct PlanDayStats: Equatable {
    let exerciseCount: Int
    let blockCount: Int
    let estimatedVolumeKG: Double

    static let empty = PlanDayStats(exerciseCount: 0, blockCount: 0, estimatedVolumeKG: 0)
}

struct ExerciseHistorySummary: Equatable {
    let entryCount: Int
    let latestLoad: Double
    let maxLoad: Double
    let loadDelta: Double
    let latestDateISO: String

    static let empty = ExerciseHistorySummary(
        entryCount: 0,
        latestLoad: 0,
        maxLoad: 0,
        loadDelta: 0,
        latestDateISO: ""
    )
}

struct TopExerciseSummary: Equatable, Identifiable {
    let id: UUID
    let exerciseName: String
    let loggedCount: Int
    let sessionCount: Int

    init(id: UUID = UUID(), exerciseName: String, loggedCount: Int, sessionCount: Int) {
        self.id = id
        self.exerciseName = exerciseName
        self.loggedCount = loggedCount
        self.sessionCount = sessionCount
    }
}

struct RecentSessionSummary: Equatable, Identifiable {
    let id: UUID
    let sheetName: String
    let dayLabel: String
    let sessionDateISO: String
    let loggedRows: Int
    let totalRows: Int

    init(
        id: UUID = UUID(),
        sheetName: String,
        dayLabel: String,
        sessionDateISO: String,
        loggedRows: Int,
        totalRows: Int
    ) {
        self.id = id
        self.sheetName = sheetName
        self.dayLabel = dayLabel
        self.sessionDateISO = sessionDateISO
        self.loggedRows = loggedRows
        self.totalRows = totalRows
    }
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
// END TEMP: TEST HARNESS

struct InBodyScan: Equatable, Identifiable {
    let id: String  // scanDate is the natural key
    var scanDate: String
    var weightKG: Double?
    var smmKG: Double?      // Skeletal Muscle Mass
    var bfmKG: Double?      // Body Fat Mass
    var pbf: Double?        // Percent Body Fat %
    var inbodyScore: Int?   // InBody Score /100
    var vfaCM2: Double?     // Visceral Fat Area cm²
    var notes: String

    init(
        scanDate: String,
        weightKG: Double? = nil,
        smmKG: Double? = nil,
        bfmKG: Double? = nil,
        pbf: Double? = nil,
        inbodyScore: Int? = nil,
        vfaCM2: Double? = nil,
        notes: String = ""
    ) {
        self.id = scanDate
        self.scanDate = scanDate
        self.weightKG = weightKG
        self.smmKG = smmKG
        self.bfmKG = bfmKG
        self.pbf = pbf
        self.inbodyScore = inbodyScore
        self.vfaCM2 = vfaCM2
        self.notes = notes
    }
}

struct OneRepMaxFieldState: Equatable, Identifiable {
    let id: String
    let liftName: String
    var inputText: String
    var lastUpdated: Date?

    var isValid: Bool {
        guard let value = Double(inputText.replacingOccurrences(of: ",", with: ".")) else {
            return inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return value >= 20 && value <= 300
    }

    var validationMessage: String {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ""
        }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else {
            return "Enter a numeric value."
        }
        if value < 20 {
            return "Minimum 20 kg."
        }
        if value > 300 {
            return "Maximum 300 kg."
        }
        return ""
    }

    var parsedValue: Double? {
        let trimmed = inputText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), value >= 20, value <= 300 else {
            return nil
        }
        return value
    }

    var lastUpdatedText: String {
        guard let date = lastUpdated, date != .distantPast else {
            return "Not set"
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
