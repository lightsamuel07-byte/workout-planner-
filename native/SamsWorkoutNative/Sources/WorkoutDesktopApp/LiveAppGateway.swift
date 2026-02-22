import Foundation
import WorkoutCore
import WorkoutIntegrations
import WorkoutPersistence

enum LiveGatewayError: LocalizedError {
    case setupIncomplete
    case missingSpreadsheetID
    case missingAuthToken
    case noWeeklyPlanSheets
    case noPlanData
    case noWorkoutForToday

    var errorDescription: String? {
        switch self {
        case .setupIncomplete:
            return "Setup is incomplete. Add Anthropic API key and Spreadsheet ID first."
        case .missingSpreadsheetID:
            return "Google Spreadsheet ID is required."
        case .missingAuthToken:
            return "Google auth token is missing. Set a token path in setup and re-auth."
        case .noWeeklyPlanSheets:
            return "No weekly plan sheets were found."
        case .noPlanData:
            return "No plan data was found in local files or Google Sheets."
        case .noWorkoutForToday:
            return "No workout found for today in the latest weekly sheet."
        }
    }
}

struct LiveAppGateway: NativeAppGateway {
    private let integrations: IntegrationsFacade
    private let configStore: AppConfigurationStore
    private let bootstrap: PersistenceBootstrap
    private let fileManager: FileManager
    private let nowProvider: () -> Date

    init(
        integrations: IntegrationsFacade = IntegrationsFacade(),
        configStore: AppConfigurationStore = FileAppConfigurationStore(),
        bootstrap: PersistenceBootstrap = PersistenceBootstrap(),
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.integrations = integrations
        self.configStore = configStore
        self.bootstrap = bootstrap
        self.fileManager = fileManager
        self.nowProvider = nowProvider
    }

    func initialRoute() -> AppRoute {
        .dashboard
    }

    func loadDashboardDays() -> [DayPlanSummary] {
        if let snapshot = try? loadLocalPlanSnapshot(), !snapshot.days.isEmpty {
            return snapshot.days.map { day in
                DayPlanSummary(
                    id: day.dayLabel.lowercased(),
                    title: day.dayLabel.uppercased(),
                    source: day.source,
                    blocks: day.exercises.count
                )
            }
        }

        return [
            DayPlanSummary(id: "monday", title: "MONDAY", source: .localCache, blocks: 0),
            DayPlanSummary(id: "tuesday", title: "TUESDAY", source: .localCache, blocks: 0),
            DayPlanSummary(id: "wednesday", title: "WEDNESDAY", source: .localCache, blocks: 0),
            DayPlanSummary(id: "thursday", title: "THURSDAY", source: .localCache, blocks: 0),
            DayPlanSummary(id: "friday", title: "FRIDAY", source: .localCache, blocks: 0),
            DayPlanSummary(id: "saturday", title: "SATURDAY", source: .localCache, blocks: 0),
            DayPlanSummary(id: "sunday", title: "SUNDAY", source: .localCache, blocks: 0),
        ]
    }

    func generatePlan(input: PlanGenerationInput) async throws -> String {
        let config = try requireGenerationSetup()

        let fortInputMap = [
            "Monday": input.monday,
            "Wednesday": input.wednesday,
            "Friday": input.friday,
        ]
        let (fortContext, fortMetadata) = buildFortCompilerContext(dayTextMap: fortInputMap)
        let aliases = loadExerciseAliases()
        let priorSupplemental = try await loadPriorSupplementalForProgression(config: config)
        let progressionRules = buildProgressionDirectives(priorSupplemental: priorSupplemental)
        let planDirectives = progressionRules.map { $0.asPlanDirective() }
        let directivesBlock = formatDirectivesForPrompt(progressionRules)
        let dbContext = buildRecentDBContext()
        let prompt = buildGenerationPrompt(
            input: input,
            fortContext: fortContext,
            dbContext: dbContext,
            progressionDirectivesBlock: directivesBlock
        )

        let anthropic = integrations.makeAnthropicClient(
            apiKey: config.anthropicAPIKey,
            model: "claude-sonnet-4-5",
            maxTokens: 4096
        )

        let generation = try await anthropic.generatePlan(
            systemPrompt: "You generate deterministic weekly workout plans in strict markdown format.",
            userPrompt: prompt
        )
        var plan = generation.text
        var repairResult = applyDeterministicRepairs(
            planText: plan,
            progressionDirectives: planDirectives,
            fortMetadata: fortMetadata,
            exerciseAliases: aliases
        )
        plan = repairResult.planText

        var validation = validatePlan(plan, progressionDirectives: planDirectives)
        var fidelity = validateFortFidelity(
            planText: plan,
            metadata: fortMetadata,
            exerciseAliases: aliases
        )

        var unresolved: [Any] = validation.violations.map { $0 as Any } + fidelity.violations.map { $0 as Any }
        var correctionAttempts = 0
        while !unresolved.isEmpty, correctionAttempts < 2 {
            let correctionPrompt = buildCorrectionPrompt(
                plan: plan,
                unresolvedViolations: unresolved,
                fortCompilerContext: fortContext,
                fortFidelitySummary: fidelity.summary
            )
            let correction = try await anthropic.generatePlan(
                systemPrompt: nil,
                userPrompt: correctionPrompt
            )
            plan = correction.text
            let correctionRepair = applyDeterministicRepairs(
                planText: plan,
                progressionDirectives: planDirectives,
                fortMetadata: fortMetadata,
                exerciseAliases: aliases
            )
            repairResult.lockedApplied += correctionRepair.lockedApplied
            repairResult.rangeCollapsed += correctionRepair.rangeCollapsed
            repairResult.anchorInsertions += correctionRepair.anchorInsertions
            plan = correctionRepair.planText

            validation = validatePlan(plan, progressionDirectives: planDirectives)
            fidelity = validateFortFidelity(
                planText: plan,
                metadata: fortMetadata,
                exerciseAliases: aliases
            )
            unresolved = validation.violations.map { $0 as Any } + fidelity.violations.map { $0 as Any }
            correctionAttempts += 1
        }

        let validationSummary = """
        \(validation.summary) \(fidelity.summary) \
        Locked directives applied: \(repairResult.lockedApplied). \
        Range collapses: \(repairResult.rangeCollapsed). \
        Fort anchors auto-inserted: \(repairResult.anchorInsertions). \
        Correction attempts: \(correctionAttempts). \
        Unresolved violations: \(unresolved.count).
        """

        let sheetName = weeklySheetName(referenceDate: nowProvider())
        let localFile = try savePlanLocally(
            planText: plan,
            sheetName: sheetName,
            validationSummary: validationSummary,
            fidelitySummary: fidelity.summary
        )

        let rows = makeSheetRows(
            planText: plan,
            validationSummary: validationSummary,
            fidelitySummary: fidelity.summary
        )

        var sheetStatus = "Google Sheets write skipped (auth token unavailable)."
        if let sheetsClient = try? await makeSheetsClient(config: config) {
            do {
                try await sheetsClient.writeWeeklyPlanRows(
                    sheetName: sheetName,
                    rows: rows,
                    archiveExisting: true
                )
                sheetStatus = "Google Sheets updated successfully."
            } catch {
                sheetStatus = "Google Sheets write failed: \(error.localizedDescription)"
            }
        }

        return """
        Generated \(sheetName).
        Local file: \(localFile.lastPathComponent)
        \(sheetStatus)
        Validation: \(validationSummary)
        Fort fidelity: \(fidelity.summary)
        """
    }

    func loadExerciseHistory(exerciseName: String) -> [ExerciseHistoryPoint] {
        guard let database = try? openDatabase() else {
            return []
        }

        let points = (try? database.fetchExerciseHistory(exerciseName: exerciseName, limit: 24)) ?? []
        return points.map { point in
            ExerciseHistoryPoint(
                id: UUID(),
                dateISO: point.sessionDateISO,
                load: point.load,
                reps: point.reps,
                notes: point.notes
            )
        }
    }

    func loadExerciseCatalog(limit: Int = 200) -> [String] {
        guard let database = try? openDatabase() else {
            return []
        }
        return (try? database.fetchExerciseCatalog(limit: limit)) ?? []
    }

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

        let dbPath = try workoutDatabasePath()
        if fileManager.fileExists(atPath: dbPath) {
            try fileManager.removeItem(atPath: dbPath)
        }

        let database = try openDatabase()
        let syncService = WorkoutSyncService(database: database)

        var daySessionsImported = 0
        var exerciseRowsImported = 0
        var loggedRowsImported = 0

        for sheetName in weeklySheets {
            let values = try await sheetsClient.readSheetAtoH(sheetName: sheetName)
            let workouts = GoogleSheetsClient.parseDayWorkouts(values: values)
            for workout in workouts {
                let entries = workout.exercises.map { exercise -> WorkoutSyncEntry in
                    let parsed = Self.parseExistingLog(exercise.log)
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
                    !$0.logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }.count
            }
        }

        let summary = try database.countSummary()
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

    func loadPlanSnapshot() async throws -> PlanSnapshot {
        if let local = try? loadLocalPlanSnapshot(), !local.days.isEmpty {
            return local
        }

        let config = try requireSheetsSetup()
        let sheetsClient = try await makeSheetsClient(config: config)
        let sheetNames = try await sheetsClient.fetchSheetNames()
        guard let mostRecent = GoogleSheetsClient.mostRecentWeeklyPlanSheet(sheetNames) else {
            throw LiveGatewayError.noWeeklyPlanSheets
        }

        let values = try await sheetsClient.readSheetAtoH(sheetName: mostRecent)
        let days = sheetDaysToPlanDays(values: values, source: .googleSheets)
        guard !days.isEmpty else {
            throw LiveGatewayError.noPlanData
        }

        return PlanSnapshot(
            title: mostRecent,
            source: .googleSheets,
            days: days,
            summary: "Loaded from Google Sheets fallback."
        )
    }

    func loadTodayLoggerSession() async throws -> LoggerSessionState {
        let config = try requireSheetsSetup()
        let sheetsClient = try await makeSheetsClient(config: config)
        let sheetNames = try await sheetsClient.fetchSheetNames()
        guard let mostRecent = GoogleSheetsClient.mostRecentWeeklyPlanSheet(sheetNames) else {
            throw LiveGatewayError.noWeeklyPlanSheets
        }

        let values = try await sheetsClient.readSheetAtoH(sheetName: mostRecent)
        let workouts = GoogleSheetsClient.parseDayWorkouts(values: values)
        guard !workouts.isEmpty else {
            throw LiveGatewayError.noPlanData
        }

        let todayName = dayName(for: nowProvider())
        let selected = workouts.first(where: { $0.dayName.caseInsensitiveCompare(todayName) == .orderedSame }) ?? workouts.first
        guard let selected else {
            throw LiveGatewayError.noWorkoutForToday
        }

        let drafts = selected.exercises.map { exercise in
            let parsed = Self.parseExistingLog(exercise.log)
            return WorkoutLogDraft(
                sourceRow: exercise.sourceRow,
                block: exercise.block,
                exercise: exercise.exercise,
                sets: exercise.sets,
                reps: exercise.reps,
                load: exercise.load,
                rest: exercise.rest,
                notes: exercise.notes,
                existingLog: exercise.log,
                performance: parsed.performance,
                rpe: parsed.rpe,
                noteEntry: parsed.notes
            )
        }

        return LoggerSessionState(
            sheetName: mostRecent,
            dayLabel: selected.dayLabel,
            source: .googleSheets,
            drafts: drafts
        )
    }

    func saveLoggerSession(_ session: LoggerSessionState) async throws -> WorkoutDBSummary {
        if session.sheetName.isEmpty || session.dayLabel.isEmpty {
            return try openDatabase().countSummary()
        }

        let config = try requireSheetsSetup()
        let sheetsClient = try await makeSheetsClient(config: config)
        let finalEntries = session.drafts.map { draft in
            (draft, canonicalLogText(for: draft))
        }

        let updates = finalEntries.compactMap { draft, logText -> ValueRangeUpdate? in
            if logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil
            }
            return ValueRangeUpdate(
                range: "'\(session.sheetName)'!H\(draft.sourceRow)",
                values: [[logText]]
            )
        }

        try await sheetsClient.batchUpdateLogs(updates)

        let syncEntries = finalEntries.compactMap { draft, logText -> WorkoutSyncEntry? in
            if logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil
            }
            return WorkoutSyncEntry(
                sourceRow: draft.sourceRow,
                exerciseName: draft.exercise,
                block: draft.block,
                prescribedSets: draft.sets,
                prescribedReps: draft.reps,
                prescribedLoad: draft.load,
                prescribedRest: draft.rest,
                prescribedNotes: draft.notes,
                logText: logText,
                explicitRPE: draft.rpe,
                parsedNotes: draft.noteEntry
            )
        }

        let fallbackDayName = GoogleSheetsClient.dayNameFromLabel(session.dayLabel) ?? dayName(for: nowProvider())
        let syncService = try makeSyncService()
        return try syncService.sync(
            input: WorkoutSyncSessionInput(
                sheetName: session.sheetName,
                dayLabel: session.dayLabel,
                fallbackDayName: fallbackDayName,
                fallbackDateISO: isoDate(nowProvider()),
                entries: syncEntries
            )
        )
    }

    func loadProgressSummary() -> ProgressSummary {
        guard let database = try? openDatabase(),
              let summary = try? database.fetchProgressSummary()
        else {
            return .empty
        }

        let completionRate: Double
        if summary.totalRows == 0 {
            completionRate = 0
        } else {
            completionRate = (Double(summary.loggedRows) / Double(summary.totalRows)) * 100
        }

        return ProgressSummary(
            completionRateText: String(format: "Completion rate: %.1f%%", completionRate),
            weeklyVolumeText: String(format: "Avg weekly volume (last 6): %.0f", summary.averageWeeklyVolume),
            recentLoggedText: "Recent logs (14d): \(summary.recentLoggedRows)",
            sourceText: "Source: Local DB cache"
        )
    }

    func loadWeeklyReviewSummaries() -> [WeeklyReviewSummary] {
        guard let database = try? openDatabase(),
              let summaries = try? database.fetchWeeklySummaries(limit: 12)
        else {
            return []
        }

        return summaries.map { row in
            let completion = row.totalCount == 0 ? 0 : (Double(row.loggedCount) / Double(row.totalCount)) * 100
            return WeeklyReviewSummary(
                sheetName: row.sheetName,
                sessions: row.sessions,
                loggedCount: row.loggedCount,
                totalCount: row.totalCount,
                completionRateText: String(format: "%.1f%%", completion)
            )
        }
    }
}

private extension LiveAppGateway {
    static let dayHeaderRegex = try! NSRegularExpression(pattern: "^##\\s+(.+)$", options: [])
    static let exerciseHeaderRegex = try! NSRegularExpression(pattern: "^###\\s+([A-Z]\\d+)\\.\\s+(.+)$", options: [.caseInsensitive])
    static let prescriptionRegex = try! NSRegularExpression(pattern: "^-\\s*(\\d+)\\s*x\\s*([\\d:]+)\\s*@\\s*([\\d]+(?:\\.\\d+)?)\\s*kg\\b", options: [.caseInsensitive])
    static let rangeRegex = try! NSRegularExpression(pattern: "(\\d+)\\s*[-–]\\s*(\\d+)", options: [])

    struct RepairOutcome {
        var planText: String
        var lockedApplied: Int
        var rangeCollapsed: Int
        var anchorInsertions: Int
    }

    func makeLocalRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    func nsRange(_ value: String) -> NSRange {
        NSRange(value.startIndex..<value.endIndex, in: value)
    }

    func requireGenerationSetup() throws -> NativeAppConfiguration {
        let config = configStore.load()
        let key = config.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sheet = config.spreadsheetID.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty || sheet.isEmpty {
            throw LiveGatewayError.setupIncomplete
        }
        return config
    }

    func requireSheetsSetup() throws -> NativeAppConfiguration {
        let config = configStore.load()
        let sheet = config.spreadsheetID.trimmingCharacters(in: .whitespacesAndNewlines)
        if sheet.isEmpty {
            throw LiveGatewayError.missingSpreadsheetID
        }
        return config
    }

    func modeStatusText(config: NativeAppConfiguration) -> String {
        let authHint = config.googleAuthHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let authText: String
        if authHint.isEmpty {
            authText = "Google auth not configured"
        } else if authHint.lowercased().hasPrefix("bearer ") {
            authText = "Google auth via bearer token hint"
        } else if authHint.hasPrefix("ya29.") || authHint.hasPrefix("eyJ") {
            authText = "Google auth via inline token hint"
        } else if fileManager.fileExists(atPath: authHint) {
            authText = "Google auth via OAuth token: \(authHint)"
        } else {
            authText = "Google auth hint path not found: \(authHint)"
        }

        let anthroConfigured = !config.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let anthropicText = anthroConfigured ? "Anthropic key configured in app setup" : "Anthropic key missing in app setup"

        return "Local native mode with Google Sheets as source of truth (\(authText); \(anthropicText))"
    }

    func appSupportDirectoryURL() -> URL {
        URL(fileURLWithPath: integrations.authSessionManager.defaultAppSupportDirectory(), isDirectory: true)
    }

    func outputDirectoryURL() throws -> URL {
        let directory = appSupportDirectoryURL().appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func dataDirectoryURL() throws -> URL {
        let directory = appSupportDirectoryURL().appendingPathComponent("data", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func workoutDatabasePath() throws -> String {
        try dataDirectoryURL().appendingPathComponent("workout_history.db").path
    }

    func openDatabase() throws -> WorkoutDatabase {
        try bootstrap.makeWorkoutDatabase(at: workoutDatabasePath())
    }

    func makeSyncService() throws -> WorkoutSyncService {
        WorkoutSyncService(database: try openDatabase())
    }

    func makeSheetsClient(config: NativeAppConfiguration) async throws -> GoogleSheetsClient {
        let token = try await resolveAuthToken(config: config)
        return integrations.makeGoogleSheetsClient(
            spreadsheetID: config.spreadsheetID,
            authToken: token
        )
    }

    func resolveAuthToken(config: NativeAppConfiguration) async throws -> String {
        let hint = config.googleAuthHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hint.isEmpty {
            if hint.lowercased().hasPrefix("bearer ") {
                let token = String(hint.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    return token
                }
            }

            if hint.hasPrefix("ya29.") || hint.hasPrefix("eyJ") {
                return hint
            }

            if fileManager.fileExists(atPath: hint) {
                return try await integrations.authSessionManager.resolveOAuthAccessToken(tokenFilePath: hint)
            }

            if let token = parseAccessTokenFromJSONString(hint) {
                return token
            }
        }

        let env = ProcessInfo.processInfo.environment
        if let envToken = env["GOOGLE_OAUTH_ACCESS_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envToken.isEmpty {
            return envToken
        }

        let authEnv = integrations.authSessionManager.loadEnvironment(from: env)
        if let tokenPath = authEnv.oauthTokenPath, fileManager.fileExists(atPath: tokenPath) {
            return try await integrations.authSessionManager.resolveOAuthAccessToken(tokenFilePath: tokenPath)
        }

        throw LiveGatewayError.missingAuthToken
    }

    func parseAccessTokenFromJSONString(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = (object["access_token"] as? String) ?? (object["token"] as? String),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return token
    }

    func weeklySheetName(referenceDate: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: referenceDate)
        let mondayOffset = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: referenceDate) ?? referenceDate
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "M/d/yyyy"
        return "Weekly Plan (\(formatter.string(from: monday)))"
    }

    func buildGenerationPrompt(
        input: PlanGenerationInput,
        fortContext: String,
        dbContext: String,
        progressionDirectivesBlock: String
    ) -> String {
        """
        You are an expert strength and conditioning coach creating a personalized weekly workout plan.

        CRITICAL: NO RANGES - use single values only (e.g., "15 reps" not "12-15", "24 kg" not "22-26 kg")

        \(fortContext)

        RECENT WORKOUT HISTORY (LOCAL DB CONTEXT):
        \(dbContext)

        \(progressionDirectivesBlock)

        FORT WORKOUT CONVERSION (CRITICAL):
        - The Fort workouts below (Mon/Wed/Fri) are raw inputs and MUST be converted into markdown exercise rows.
        - Treat "FORT COMPILER DIRECTIVES" section order and listed exercise anchors as hard constraints.
        - Keep day section order aligned with detected Fort sections and include each anchor exercise at least once.
        - Convert each exercise to:
          ### A1. [Exercise Name]
          - [Sets] x [Reps] @ [Load] kg
          - **Rest:** [period]
          - **Notes:** [coaching cues]
        - Never output section labels/instruction lines as exercises.

        Monday input:
        \(input.monday)

        Wednesday input:
        \(input.wednesday)

        Friday input:
        \(input.friday)

        CORE PRINCIPLES:
        - Supplemental days (Tue/Thu/Sat) support Fort work with arm/shoulder/upper chest/back detail.
        - Preserve explicit keep/stay-here progression constraints from prior logs.
        - Never increase both reps and load in the same week for the same exercise.

        MANDATORY HARD RULES:
        - Equipment: No belt on pulls, standing calves only, no split squats.
        - Dumbbells: even-number loads only (no odd DB loads except main barbell lifts).
        - Biceps: rotate grips (supinated -> neutral -> pronated), no repeated adjacent supplemental-day grip.
        - Triceps: vary attachments Tue/Fri/Sat, no single-arm D-handle triceps on Saturday.
        - Carries: Tuesday only.
        - Canonical log format in sheets: performance | RPE x | Notes: ...

        OUTPUT REQUIREMENTS:
        - Use ## day headers and ### block.exercise headers.
        - Include all seven days (Mon-Sun).
        - Keep A:H sheet compatibility (Block, Exercise, Sets, Reps, Load, Rest, Notes, Log).
        - American spelling.
        """
    }

    func buildCorrectionPrompt(
        plan: String,
        unresolvedViolations: [Any],
        fortCompilerContext: String,
        fortFidelitySummary: String
    ) -> String {
        let rendered = unresolvedViolations.prefix(20).map { violation -> String in
            if let planViolation = violation as? PlanViolation {
                return "- \(planViolation.code) | \(planViolation.day) | \(planViolation.exercise) | \(planViolation.message)"
            }
            if let fidelityViolation = violation as? FortFidelityViolation {
                return "- \(fidelityViolation.code) | \(fidelityViolation.day) | \(fidelityViolation.exercise) | \(fidelityViolation.message)"
            }
            return "- unknown_violation"
        }.joined(separator: "\n")

        return """
        Correct this workout plan to satisfy all listed validation violations.

        Violations:
        \(rendered)

        Current fort fidelity status: \(fortFidelitySummary)

        FORT COMPILER DIRECTIVES:
        \(fortCompilerContext)

        Hard requirements:
        - Keep overall structure and exercise order unless violation requires change.
        - Preserve Fort day content and supplemental intent.
        - Keep no-range rule in prescription lines.
        - Keep dumbbell parity rule (even DB loads, except main barbell lifts).
        - Respect explicit keep/stay-here progression constraints from prior logs.
        - Never emit section labels or instructional lines as exercises.

        Return the full corrected plan in the same markdown format.

        PLAN:
        \(plan)
        """
    }

    func loadPriorSupplementalForProgression(config: NativeAppConfiguration) async throws -> [String: [PriorSupplementalExercise]] {
        guard let sheetsClient = try? await makeSheetsClient(config: config) else {
            return [:]
        }

        let sheetNames = try await sheetsClient.fetchSheetNames()
        guard let mostRecent = GoogleSheetsClient.mostRecentWeeklyPlanSheet(sheetNames) else {
            return [:]
        }

        let values = try await sheetsClient.readSheetAtoH(sheetName: mostRecent)
        let supplemental = GoogleSheetsClient.parseSupplementalWorkouts(values: values)
        var output: [String: [PriorSupplementalExercise]] = [:]
        for day in ["Tuesday", "Thursday", "Saturday"] {
            output[day] = (supplemental[day] ?? []).map { row in
                PriorSupplementalExercise(
                    exercise: row.exercise,
                    reps: row.reps,
                    load: row.load,
                    log: row.log
                )
            }
        }
        return output
    }

    func buildRecentDBContext(maxRows: Int = 40, maxChars: Int = 3200) -> String {
        guard let database = try? openDatabase(),
              let rows = try? database.fetchRecentLogContextRows(limit: maxRows),
              !rows.isEmpty
        else {
            return "No recent DB logs available."
        }

        var lines: [String] = ["TARGETED DB CONTEXT (RECENT LOGS):"]
        for row in rows {
            let line = "- \(row.sessionDateISO) | \(row.dayLabel) | \(row.exerciseName) | \(row.sets)x\(row.reps) @ \(row.load)kg | log: \(row.logText)"
            lines.append(line)
        }
        let joined = lines.joined(separator: "\n")
        if joined.count <= maxChars {
            return joined
        }
        return String(joined.prefix(maxChars))
    }

    func applyDeterministicRepairs(
        planText: String,
        progressionDirectives: [ProgressionDirective],
        fortMetadata: FortCompilerMetadata?,
        exerciseAliases: [String: String]
    ) -> RepairOutcome {
        var repaired = planText
        repaired = applyExerciseSwaps(repaired, aliases: exerciseAliases)
        repaired = enforceEvenDumbbellLoads(repaired)

        let locked = applyLockedDirectivesToPlan(planText: repaired, directives: progressionDirectives)
        repaired = locked.0

        let rangeRepair = collapseRangesInPrescriptionLines(repaired)
        repaired = rangeRepair.planText

        let anchorRepair = repairPlanFortAnchors(
            planText: repaired,
            metadata: fortMetadata,
            exerciseAliases: exerciseAliases
        )
        repaired = canonicalizeExerciseNames(anchorRepair.0)

        return RepairOutcome(
            planText: repaired,
            lockedApplied: locked.1,
            rangeCollapsed: rangeRepair.collapsedCount,
            anchorInsertions: anchorRepair.1.inserted
        )
    }

    func applyExerciseSwaps(_ planText: String, aliases: [String: String]) -> String {
        if aliases.isEmpty {
            return planText
        }

        let sortedAliases = aliases.keys.sorted { lhs, rhs in
            lhs.count > rhs.count
        }
        var updated = planText

        for raw in sortedAliases {
            guard let replacement = aliases[raw], !replacement.isEmpty else {
                continue
            }
            let pattern = NSRegularExpression.escapedPattern(for: raw)
            let regex = makeLocalRegex(pattern, options: [.caseInsensitive])
            updated = regex.stringByReplacingMatches(
                in: updated,
                options: [],
                range: nsRange(updated),
                withTemplate: replacement
            )
        }

        return updated
    }

    func enforceEvenDumbbellLoads(_ planText: String) -> String {
        let headerRegex = makeLocalRegex("^\\s*###\\s+[A-Z]\\d+\\.\\s*(.+)$", options: [.caseInsensitive])
        let loadRegex = makeLocalRegex("@\\s*([\\d]+(?:\\.\\d+)?)\\s*kg\\b", options: [.caseInsensitive])

        var currentIsDB = false
        var currentIsMainLift = false
        let normalizer = getNormalizer()
        var lines = planText.components(separatedBy: .newlines)

        for index in lines.indices {
            let line = lines[index]
            if let headerMatch = headerRegex.firstMatch(in: line, options: [], range: nsRange(line)),
               let nameRange = Range(headerMatch.range(at: 1), in: line) {
                let exerciseName = String(line[nameRange])
                currentIsDB = normalizer.isDBExercise(exerciseName)
                currentIsMainLift = normalizer.isMainPlateLift(exerciseName)
                continue
            }

            if !currentIsDB || currentIsMainLift {
                continue
            }

            if line.range(of: "@") == nil || line.lowercased().range(of: "kg") == nil {
                continue
            }

            let replaced = loadRegex.stringByReplacingMatches(
                in: line,
                options: [],
                range: nsRange(line),
                withTemplate: "@ $1 kg"
            )
            let match = loadRegex.firstMatch(in: replaced, options: [], range: nsRange(replaced))
            guard let loadMatch = match,
                  let loadRange = Range(loadMatch.range(at: 1), in: replaced),
                  let raw = Double(replaced[loadRange])
            else {
                continue
            }

            let rounded = Int(round(raw))
            if rounded % 2 == 0 {
                continue
            }

            let lowerEven = rounded - 1
            let upperEven = rounded + 1
            let chosen = abs(raw - Double(lowerEven)) <= abs(raw - Double(upperEven)) ? lowerEven : upperEven
            lines[index] = loadRegex.stringByReplacingMatches(
                in: replaced,
                options: [],
                range: nsRange(replaced),
                withTemplate: "@ \(chosen) kg"
            )
        }

        return lines.joined(separator: "\n")
    }

    func collapseRangesInPrescriptionLines(_ planText: String) -> (planText: String, collapsedCount: Int) {
        var lines = planText.components(separatedBy: .newlines)
        var collapsedCount = 0

        for index in lines.indices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.hasPrefix("-") || !trimmed.contains(" x ") || !trimmed.contains("@") {
                continue
            }

            guard let match = Self.rangeRegex.firstMatch(in: line, options: [], range: nsRange(line)),
                  let lowRange = Range(match.range(at: 1), in: line),
                  let highRange = Range(match.range(at: 2), in: line),
                  let low = Int(line[lowRange]),
                  let high = Int(line[highRange])
            else {
                continue
            }

            let replacement: String
            let atIndex = line.firstIndex(of: "@")
            if let atIndex, lowRange.lowerBound > atIndex {
                let midpoint = (Double(low) + Double(high)) / 2.0
                replacement = String(format: "%.1f", midpoint).replacingOccurrences(of: "\\.0$", with: "", options: .regularExpression)
            } else {
                replacement = String(high)
            }

            let rangeText = String(line[lowRange.lowerBound..<highRange.upperBound])
            lines[index] = line.replacingOccurrences(of: rangeText, with: replacement, options: [], range: line.range(of: rangeText))
            collapsedCount += 1
        }

        return (lines.joined(separator: "\n"), collapsedCount)
    }

    func canonicalizeExerciseNames(_ planText: String) -> String {
        let headerRegex = makeLocalRegex("^(\\s*###\\s+[A-Z]\\d+\\.\\s*)(.+)$", options: [.caseInsensitive])
        let normalizer = getNormalizer()
        var lines = planText.components(separatedBy: .newlines)

        for index in lines.indices {
            let line = lines[index]
            guard let match = headerRegex.firstMatch(in: line, options: [], range: nsRange(line)),
                  let prefixRange = Range(match.range(at: 1), in: line),
                  let exerciseRange = Range(match.range(at: 2), in: line)
            else {
                continue
            }

            let prefix = String(line[prefixRange])
            let rawName = String(line[exerciseRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let canonical = normalizer.canonicalName(rawName)
            if canonical != rawName {
                lines[index] = "\(prefix)\(canonical)"
            }
        }

        return lines.joined(separator: "\n")
    }

    func loadExerciseAliases() -> [String: String] {
        var candidates: [URL] = []
        candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("exercise_swaps.yaml"))
        candidates.append(appSupportDirectoryURL().appendingPathComponent("exercise_swaps.yaml"))

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            if let content = try? String(contentsOf: candidate, encoding: .utf8) {
                let parsed = parseExerciseAliasesFromYAML(content)
                if !parsed.isEmpty {
                    return parsed
                }
            }
        }

        return [:]
    }

    func parseExerciseAliasesFromYAML(_ content: String) -> [String: String] {
        var mapping: [String: String] = [:]
        var inSwaps = false

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if trimmed == "exercise_swaps:" {
                inSwaps = true
                continue
            }

            if inSwaps, !line.hasPrefix("  "), !line.hasPrefix("\t") {
                inSwaps = false
            }

            if !inSwaps {
                continue
            }

            guard let separator = trimmed.firstIndex(of: ":") else {
                continue
            }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let value = trimmed[trimmed.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty, !value.isEmpty {
                mapping[String(key)] = String(value)
            }
        }

        return mapping
    }

    func savePlanLocally(
        planText: String,
        sheetName: String,
        validationSummary: String,
        fidelitySummary: String
    ) throws -> URL {
        let outputDirectory = try outputDirectoryURL()
        let planURL = outputDirectory.appendingPathComponent(localPlanFileName(for: sheetName))

        if fileManager.fileExists(atPath: planURL.path) {
            let archiveDir = outputDirectory.appendingPathComponent("archive", isDirectory: true)
            try fileManager.createDirectory(at: archiveDir, withIntermediateDirectories: true)
            let baseName = planURL.deletingPathExtension().lastPathComponent + "_archived_" + archiveTimestamp(nowProvider())
            var archivedURL = archiveDir.appendingPathComponent(baseName + ".md")
            var suffix = 1
            while fileManager.fileExists(atPath: archivedURL.path) {
                archivedURL = archiveDir.appendingPathComponent(baseName + "_\(suffix).md")
                suffix += 1
            }
            try fileManager.moveItem(at: planURL, to: archivedURL)
        }

        try planText.data(using: .utf8)?.write(to: planURL, options: [.atomic])

        let summaryURL = outputDirectory.appendingPathComponent(
            planURL.deletingPathExtension().lastPathComponent + "_summary.md"
        )
        let summaryText = """
        Sheet: \(sheetName)
        Validation: \(validationSummary)
        Fort fidelity: \(fidelitySummary)
        Generated at: \(isoDateTime(nowProvider()))
        """
        try summaryText.data(using: .utf8)?.write(to: summaryURL, options: [.atomic])

        return planURL
    }

    func loadLocalPlanSnapshot() throws -> PlanSnapshot {
        let outputDirectory = try outputDirectoryURL()
        let files = try fileManager.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let planFiles = files.filter { url in
            let name = url.lastPathComponent.lowercased()
            return name.hasPrefix("workout_plan_") && name.hasSuffix(".md") && !name.contains("_summary")
        }
        let sorted = planFiles.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
        guard let latest = sorted.first else {
            throw LiveGatewayError.noPlanData
        }

        let text = try String(contentsOf: latest, encoding: .utf8)
        let days = markdownDaysToPlanDays(planText: text, source: .localCache)
        return PlanSnapshot(
            title: latest.lastPathComponent,
            source: .localCache,
            days: days,
            summary: "Loaded from local markdown artifact."
        )
    }

    func localPlanFileName(for sheetName: String) -> String {
        let slug = sheetName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "workout_plan_\(slug).md"
    }

    func makeSheetRows(planText: String, validationSummary: String, fidelitySummary: String) -> [[String]] {
        let days = markdownDaysToPlanDays(planText: planText, source: .localCache)
        var rows: [[String]] = []
        rows.append(["Workout Plan - Generated \(isoDateTime(nowProvider()))"])
        rows.append([])

        for day in days {
            rows.append([day.dayLabel])
            rows.append([])
            rows.append(["Block", "Exercise", "Sets", "Reps", "Load (kg)", "Rest", "Notes", "Log"])

            for exercise in day.exercises {
                rows.append([
                    exercise.block,
                    exercise.exercise,
                    exercise.sets,
                    exercise.reps,
                    exercise.load,
                    exercise.rest,
                    exercise.notes,
                    "",
                ])
            }
            rows.append([])
        }

        rows.append(["AI Generation Summary", "", "", "", "", "", "", ""])
        rows.append(["Validation", "", "", "", "", "", validationSummary, ""])
        rows.append(["Fort Fidelity", "", "", "", "", "", fidelitySummary, ""])

        return rows.map { GoogleSheetsClient.enforceEightColumnSchema($0) }
    }

    func markdownDaysToPlanDays(planText: String, source: DataSourceLabel) -> [PlanDayDetail] {
        let lines = planText.components(separatedBy: .newlines)
        var days: [PlanDayDetail] = []
        var currentDayLabel: String?
        var currentExercises: [PlanExerciseRow] = []
        var index = 0

        func flushDay() {
            guard let dayLabel = currentDayLabel else {
                return
            }
            days.append(
                PlanDayDetail(
                    id: dayLabel,
                    dayLabel: dayLabel,
                    source: source,
                    exercises: currentExercises
                )
            )
            currentDayLabel = nil
            currentExercises = []
        }

        while index < lines.count {
            let rawLine = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)

            if let match = firstMatch(Self.dayHeaderRegex, text: rawLine),
               let dayLabel = match[0] {
                flushDay()
                currentDayLabel = dayLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                index += 1
                continue
            }

            if let match = firstMatch(Self.exerciseHeaderRegex, text: rawLine),
               currentDayLabel != nil,
               let block = match[0],
               let exerciseName = match[1] {
                var sets = ""
                var reps = ""
                var load = ""
                var rest = ""
                var notes = ""

                var probeIndex = index + 1
                while probeIndex < lines.count {
                    let probe = lines[probeIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                    if firstMatch(Self.exerciseHeaderRegex, text: probe) != nil || firstMatch(Self.dayHeaderRegex, text: probe) != nil {
                        break
                    }

                    if let rx = firstMatch(Self.prescriptionRegex, text: probe),
                       let pSets = rx[0],
                       let pReps = rx[1],
                       let pLoad = rx[2] {
                        sets = pSets
                        reps = pReps
                        load = pLoad
                    } else if probe.lowercased().hasPrefix("- **rest:**") {
                        rest = probe.replacingOccurrences(of: "- **Rest:**", with: "", options: [.caseInsensitive]).trimmingCharacters(in: .whitespaces)
                    } else if probe.lowercased().hasPrefix("- **notes:**") {
                        notes = probe.replacingOccurrences(of: "- **Notes:**", with: "", options: [.caseInsensitive]).trimmingCharacters(in: .whitespaces)
                    }
                    probeIndex += 1
                }

                currentExercises.append(
                    PlanExerciseRow(
                        sourceRow: nil,
                        block: block,
                        exercise: exerciseName,
                        sets: sets,
                        reps: reps,
                        load: load,
                        rest: rest,
                        notes: notes,
                        log: ""
                    )
                )

                index = probeIndex
                continue
            }

            index += 1
        }

        flushDay()
        return days
    }

    func sheetDaysToPlanDays(values: [[String]], source: DataSourceLabel) -> [PlanDayDetail] {
        GoogleSheetsClient.parseDayWorkouts(values: values).map { workout in
            let rows = workout.exercises.map { exercise in
                PlanExerciseRow(
                    sourceRow: exercise.sourceRow,
                    block: exercise.block,
                    exercise: exercise.exercise,
                    sets: exercise.sets,
                    reps: exercise.reps,
                    load: exercise.load,
                    rest: exercise.rest,
                    notes: exercise.notes,
                    log: exercise.log
                )
            }
            return PlanDayDetail(
                id: workout.dayLabel,
                dayLabel: workout.dayLabel,
                source: source,
                exercises: rows
            )
        }
    }

    func canonicalLogText(for draft: WorkoutLogDraft) -> String {
        let performance = draft.performance.trimmingCharacters(in: .whitespacesAndNewlines)
        let rpe = draft.rpe.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = draft.noteEntry.trimmingCharacters(in: .whitespacesAndNewlines)

        if performance.isEmpty && rpe.isEmpty && notes.isEmpty {
            return draft.existingLog.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var parts: [String] = []
        if !performance.isEmpty {
            parts.append(performance)
        }
        if !rpe.isEmpty {
            parts.append("RPE \(rpe)")
        }
        if !notes.isEmpty {
            parts.append("Notes: \(notes)")
        }

        return parts.joined(separator: " | ")
    }

    static func parseExistingLog(_ value: String) -> (performance: String, rpe: String, notes: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ("", "", "")
        }

        var performance = ""
        var rpe = ""
        var notes = ""

        let parts = trimmed.split(separator: "|").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for part in parts {
            let lower = part.lowercased()
            if lower.hasPrefix("rpe ") {
                rpe = part.replacingOccurrences(of: "RPE", with: "", options: [.caseInsensitive]).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("notes:") {
                notes = part.replacingOccurrences(of: "Notes:", with: "", options: [.caseInsensitive]).trimmingCharacters(in: .whitespaces)
            } else if performance.isEmpty {
                performance = part
            }
        }

        return (performance, rpe, notes)
    }

    func dayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func isoDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    func archiveTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }

    func firstMatch(_ regex: NSRegularExpression, text: String) -> [String?]? {
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)) else {
            return nil
        }

        var captures: [String?] = []
        for idx in 1..<match.numberOfRanges {
            let range = match.range(at: idx)
            if range.location == NSNotFound {
                captures.append(nil)
            } else if let swiftRange = Range(range, in: text) {
                captures.append(String(text[swiftRange]))
            } else {
                captures.append(nil)
            }
        }
        return captures
    }
}
