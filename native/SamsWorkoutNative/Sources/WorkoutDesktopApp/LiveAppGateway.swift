import Foundation
import WorkoutCore
import WorkoutIntegrations
import WorkoutPersistence

final class ThreadSafeBox<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()

    init(_ value: T) {
        self.value = value
    }

    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}

enum LiveGatewayError: LocalizedError {
    case setupIncomplete
    case missingSpreadsheetID
    case invalidSpreadsheetID
    case missingAuthToken
    case noWeeklyPlanSheets
    case noPlanData
    case noWorkoutForToday
    case dbSyncFailedAfterSheetsWrite(underlyingError: String)

    var errorDescription: String? {
        switch self {
        case .setupIncomplete:
            return "Setup is incomplete. Add Anthropic API key and Spreadsheet ID first."
        case .missingSpreadsheetID:
            return "Google Spreadsheet ID is required."
        case .invalidSpreadsheetID:
            return "Google Spreadsheet ID format is invalid. Expected a 44-character alphanumeric string."
        case .missingAuthToken:
            return "Google auth token is missing. Set a token path in setup and re-auth."
        case .noWeeklyPlanSheets:
            return "No weekly plan sheets were found."
        case .noPlanData:
            return "No plan data was found in local files or Google Sheets."
        case .noWorkoutForToday:
            return "No workout found for today in the latest weekly sheet."
        case .dbSyncFailedAfterSheetsWrite(let underlyingError):
            return "Sheets updated but local DB sync failed: \(underlyingError). Try Rebuild DB Cache to re-sync."
        }
    }
}

struct LiveAppGateway: NativeAppGateway {
    enum PlanWriteMode {
        case normal
        case localOnly
    }

    private let integrations: IntegrationsFacade
    private let configStore: AppConfigurationStore
    private let bootstrap: PersistenceBootstrap
    private let fileManager: FileManager
    private let nowProvider: () -> Date
    private let planWriteMode: PlanWriteMode
    private let cachedDatabase: ThreadSafeBox<WorkoutDatabase?>

    init(
        integrations: IntegrationsFacade = IntegrationsFacade(),
        configStore: AppConfigurationStore = FileAppConfigurationStore(),
        bootstrap: PersistenceBootstrap = PersistenceBootstrap(),
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init,
        planWriteMode: PlanWriteMode = .normal
    ) {
        self.integrations = integrations
        self.configStore = configStore
        self.bootstrap = bootstrap
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        self.planWriteMode = planWriteMode
        self.cachedDatabase = ThreadSafeBox(nil)
    }

    func initialRoute() -> AppRoute {
        .dashboard
    }

    func generatePlan(input: PlanGenerationInput) async throws -> String {
        try await generatePlan(input: input, onProgress: nil)
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

    func generatePlan(
        input: PlanGenerationInput,
        onProgress: ((GenerationProgressUpdate) -> Void)?
    ) async throws -> String {
        let config = try requireGenerationSetup()
        let progressCallback = ThreadSafeBox(onProgress)
        let emitFromStream: @Sendable (GenerationProgressUpdate) -> Void = { update in
            Task { @MainActor in
                progressCallback.get()?(update)
            }
        }
        func emit(
            _ stage: GenerationProgressStage,
            _ message: String,
            streamedCharacters: Int? = nil,
            inputTokens: Int? = nil,
            outputTokens: Int? = nil,
            previewTail: String? = nil,
            correctionAttempt: Int? = nil
        ) {
            progressCallback.get()?(
                GenerationProgressUpdate(
                    stage: stage,
                    message: message,
                    streamedCharacters: streamedCharacters,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    previewTail: previewTail,
                    correctionAttempt: correctionAttempt
                )
            )
        }
        emit(.preparing, "Preparing generation inputs and setup checks.")

        let fortInputMap = [
            "Monday": input.monday,
            "Wednesday": input.wednesday,
            "Friday": input.friday,
        ]
        let (fortContext, fortMetadata) = buildFortCompilerContext(dayTextMap: fortInputMap, sectionOverrides: input.fortSectionOverrides)
        emit(.normalizingFort, "Fort input normalized locally before model request.")
        let aliases = loadExerciseAliases()
        let priorSupplemental = try await loadPriorSupplementalForProgression(config: config)
        let progressionRules = buildProgressionDirectives(priorSupplemental: priorSupplemental)
        let planDirectives = progressionRules.map { $0.asPlanDirective() }
        let directivesBlock = formatDirectivesForPrompt(progressionRules)
        let oneRepMaxes = loadOneRepMaxesFromConfig()

        // ── Two-pass: exercise selection → targeted DB context ──────────────────
        // Pass 1: ask Claude to enumerate which exercises it will program on
        // Tue/Thu/Sat. This is a cheap call (~200-300 output tokens). We use the
        // result to pull targeted DB history for ONLY those exercises, avoiding
        // the noise of fetching 40 generic recent rows that may not even be used.
        let anthropicPass1 = integrations.makeAnthropicClient(
            apiKey: config.anthropicAPIKey,
            model: "claude-sonnet-4-6",
            maxTokens: 300
        )
        let dbContext: String
        do {
            emit(.preparing, "Pass 1: selecting supplemental exercises for targeted DB context.")
            let selectionPrompt = buildExerciseSelectionPrompt(input: input, fortContext: fortContext)
            let pass1Result = try await anthropicPass1.generatePlan(
                systemPrompt: nil,
                userPrompt: selectionPrompt,
                onEvent: nil
            )
            let selected = parseSelectedExercises(from: pass1Result.text)
            if !selected.isEmpty,
               let targeted = buildTargetedDBContext(for: selected) {
                let exerciseCount = selected.values.reduce(0) { $0 + $1.count }
                emit(.preparing, "Pass 1 complete: \(exerciseCount) exercises selected, targeted DB context built.")
                dbContext = targeted
            } else {
                // Parsed OK but no DB history found — fall back to generic context.
                emit(.preparing, "Pass 1: no matching DB history for selected exercises, falling back to generic context.")
                dbContext = buildRecentDBContext()
            }
        } catch {
            // Pass 1 network error or any other failure — fall back gracefully.
            emit(.preparing, "Pass 1 failed (\(error.localizedDescription)), falling back to generic DB context.")
            dbContext = buildRecentDBContext()
        }
        // ────────────────────────────────────────────────────────────────────────

        let prompt = buildGenerationPrompt(
            input: input,
            fortContext: fortContext,
            dbContext: dbContext,
            progressionDirectivesBlock: directivesBlock,
            oneRepMaxes: oneRepMaxes
        )

        let anthropic = integrations.makeAnthropicClient(
            apiKey: config.anthropicAPIKey,
            model: "claude-sonnet-4-6",
            maxTokens: 8192
        )

        emit(.requestingModel, "Requesting plan from Anthropic.")
        let streamedCharsBox = ThreadSafeBox(0)
        let latestInputTokensBox = ThreadSafeBox<Int?>(nil)
        let latestOutputTokensBox = ThreadSafeBox<Int?>(nil)
        let latestPreviewTailBox = ThreadSafeBox("")
        let generation = try await anthropic.generatePlan(
            systemPrompt: "You generate deterministic weekly workout plans in strict markdown format.",
            userPrompt: prompt,
            onEvent: { event in
                switch event {
                case .requestStarted:
                    emitFromStream(
                        GenerationProgressUpdate(
                            stage: .streamingResponse,
                            message: "Model stream opened."
                        )
                    )
                case .messageStarted(_, let inputTokens):
                    latestInputTokensBox.set(inputTokens)
                    emitFromStream(
                        GenerationProgressUpdate(
                            stage: .streamingResponse,
                            message: "Model response started.",
                            streamedCharacters: streamedCharsBox.get(),
                            inputTokens: latestInputTokensBox.get()
                        )
                    )
                case .textDelta(let chunk, let totalCharacters):
                    streamedCharsBox.set(totalCharacters)
                    var previewTail = latestPreviewTailBox.get() + chunk
                    if previewTail.count > 320 {
                        previewTail = String(previewTail.suffix(320))
                    }
                    latestPreviewTailBox.set(previewTail)
                    emitFromStream(
                        GenerationProgressUpdate(
                            stage: .streamingResponse,
                            message: "Streaming model response…",
                            streamedCharacters: streamedCharsBox.get(),
                            inputTokens: latestInputTokensBox.get(),
                            outputTokens: latestOutputTokensBox.get(),
                            previewTail: previewTail
                        )
                    )
                case .messageDelta(_, let outputTokens):
                    if let outputTokens {
                        latestOutputTokensBox.set(outputTokens)
                    }
                    emitFromStream(
                        GenerationProgressUpdate(
                            stage: .streamingResponse,
                            message: "Streaming model response…",
                            streamedCharacters: streamedCharsBox.get(),
                            inputTokens: latestInputTokensBox.get(),
                            outputTokens: latestOutputTokensBox.get(),
                            previewTail: latestPreviewTailBox.get()
                        )
                    )
                case .messageStopped:
                    emitFromStream(
                        GenerationProgressUpdate(
                            stage: .validating,
                            message: "Model stream complete. Running deterministic repairs and validation.",
                            streamedCharacters: streamedCharsBox.get(),
                            inputTokens: latestInputTokensBox.get(),
                            outputTokens: latestOutputTokensBox.get(),
                            previewTail: latestPreviewTailBox.get()
                        )
                    )
                }
            }
        )
        let streamedChars = streamedCharsBox.get()
        let latestInputTokens = latestInputTokensBox.get()
        let latestOutputTokens = latestOutputTokensBox.get()
        var plan = stripPlanPreamble(generation.text)
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

        var unresolved: [any ViolationDescribing] = validation.violations + fidelity.violations
        var correctionAttempts = 0
        while !unresolved.isEmpty, correctionAttempts < 2 {
            emit(
                .correcting,
                "Applying correction pass \(correctionAttempts + 1) for \(unresolved.count) unresolved issue(s).",
                streamedCharacters: streamedChars,
                inputTokens: latestInputTokens ?? generation.inputTokens,
                outputTokens: latestOutputTokens ?? generation.outputTokens,
                correctionAttempt: correctionAttempts + 1
            )
            let correctionPrompt = buildCorrectionPrompt(
                plan: plan,
                unresolvedViolations: unresolved,
                fortCompilerContext: fortContext,
                fortFidelitySummary: fidelity.summary
            )
            let correction = try await anthropic.generatePlan(
                systemPrompt: nil,
                userPrompt: correctionPrompt,
                onEvent: nil
            )
            plan = stripPlanPreamble(correction.text)
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
            unresolved = validation.violations + fidelity.violations
            correctionAttempts += 1
        }

        emit(
            .writingOutputs,
            "Writing local output and preparing Google Sheets rows.",
            streamedCharacters: streamedChars,
            inputTokens: latestInputTokens ?? generation.inputTokens,
            outputTokens: latestOutputTokens ?? generation.outputTokens
        )
        let validationSummary = """
        \(validation.summary) \(fidelity.summary) \
        Locked directives applied: \(repairResult.lockedApplied). \
        Range collapses: \(repairResult.rangeCollapsed). \
        Fort anchors auto-inserted: \(repairResult.anchorInsertions). \
        Correction attempts: \(correctionAttempts). \
        Unresolved violations: \(unresolved.count).
        """

        let sheetDateGuard = sanitizedSheetReferenceDate(nowProvider())
        let sheetName = weeklySheetName(referenceDate: sheetDateGuard.date)
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
        switch planWriteMode {
        case .normal:
            if let sheetsClient = try? await makeSheetsClient(config: config) {
                emit(.syncingDatabase, "Writing plan to Google Sheets.")
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
        case .localOnly:
            sheetStatus = "Google Sheets write skipped (local-only mode)."
        }

        emit(
            .completed,
            "Generation completed successfully.",
            streamedCharacters: streamedChars,
            inputTokens: latestInputTokens ?? generation.inputTokens,
            outputTokens: latestOutputTokens ?? generation.outputTokens
        )

        return """
        Generated \(sheetName).
        Local file: \(localFile.lastPathComponent)
        \(sheetStatus)
        Date guard: \(sheetDateGuard.wasSanitized ? "Applied (far-future/past date replaced with current week)." : "Not needed.")
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

    func loadPlanSnapshot(forceRemote: Bool = false) async throws -> PlanSnapshot {
        // When not forcing remote, try local cache first for fast startup.
        if !forceRemote, let local = try? loadLocalPlanSnapshot(), !local.days.isEmpty {
            return local
        }

        // Try Google Sheets (primary source of truth).
        if let config = try? requireSheetsSetup() {
            do {
                let sheetsClient = try await makeSheetsClient(config: config)
                let sheetNames = try await sheetsClient.fetchSheetNames()
                if let preferredSheet = preferredWeeklyPlanSheetName(sheetNames) {
                    let values = try await sheetsClient.readSheetAtoH(sheetName: preferredSheet)
                    let days = sheetDaysToPlanDays(values: values, source: .googleSheets)
                    if !days.isEmpty {
                        return PlanSnapshot(
                            title: normalizedPlanTitle(preferredSheet),
                            source: .googleSheets,
                            days: days,
                            summary: normalizedPlanSummary(
                                forceRemote
                                    ? "Refreshed from Google Sheets."
                                    : "Loaded from Google Sheets."
                            )
                        )
                    }
                }
            } catch {
                // If forceRemote was requested and Sheets fails, propagate the error.
                if forceRemote {
                    throw error
                }
                // Otherwise fall through to local cache below.
            }
        }

        // Fallback: local cache (only reached when not forcing remote, or Sheets had no data).
        if let local = try? loadLocalPlanSnapshot(), !local.days.isEmpty {
            return local
        }

        throw LiveGatewayError.noPlanData
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

    func loadTopExercises(limit: Int = 5) -> [TopExerciseSummary] {
        guard let database = try? openDatabase(),
              let summaries = try? database.fetchTopExerciseSummaries(limit: limit)
        else {
            return []
        }

        return summaries.map { row in
            TopExerciseSummary(
                exerciseName: row.exerciseName,
                loggedCount: row.loggedCount,
                sessionCount: row.sessionCount
            )
        }
    }

    func loadRecentSessions(limit: Int = 8) -> [RecentSessionSummary] {
        let today = isoDate(nowProvider())
        guard let database = try? openDatabase(),
              let summaries = try? database.fetchRecentSessionSummaries(limit: limit, todayISO: today)
        else {
            return []
        }

        return summaries.map { row in
            RecentSessionSummary(
                sheetName: row.sheetName,
                dayLabel: row.dayLabel,
                sessionDateISO: row.sessionDateISO,
                loggedRows: row.loggedRows,
                totalRows: row.totalRows
            )
        }
    }

    func loadWeeklyVolumePoints(limit: Int = 12) -> [WeeklyVolumePoint] {
        guard let database = try? openDatabase(),
              let points = try? database.fetchWeeklyVolume(limit: limit)
        else {
            return []
        }

        return points.map { row in
            WeeklyVolumePoint(sheetName: row.sheetName, volume: row.volume)
        }
    }

    func loadWeeklyRPEPoints(limit: Int = 12) -> [WeeklyRPEPoint] {
        guard let database = try? openDatabase(),
              let points = try? database.fetchWeeklyRPE(limit: limit)
        else {
            return []
        }

        return points.map { row in
            WeeklyRPEPoint(sheetName: row.sheetName, averageRPE: row.averageRPE, rpeCount: row.rpeCount)
        }
    }

    func loadMuscleGroupVolumes(limit: Int = 12) -> [MuscleGroupVolume] {
        guard let database = try? openDatabase(),
              let volumes = try? database.fetchMuscleGroupVolume(limit: limit)
        else {
            return []
        }

        return volumes.map { row in
            MuscleGroupVolume(muscleGroup: row.muscleGroup, volume: row.volume, exerciseCount: row.exerciseCount)
        }
    }

    // MARK: - InBody Scans

    func loadInBodyScans() -> [InBodyScan] {
        guard let database = try? openDatabase(),
              let scans = try? database.fetchInBodyScans()
        else { return [] }

        return scans.map { s in
            InBodyScan(
                scanDate: s.scanDate,
                weightKG: s.weightKG,
                smmKG: s.smmKG,
                bfmKG: s.bfmKG,
                pbf: s.pbf,
                inbodyScore: s.inbodyScore,
                vfaCM2: s.vfaCM2,
                notes: s.notes
            )
        }
    }

    func saveInBodyScan(_ scan: InBodyScan) throws {
        let database = try openDatabase()
        let persisted = PersistedInBodyScan(
            id: 0,
            scanDate: scan.scanDate,
            weightKG: scan.weightKG,
            smmKG: scan.smmKG,
            bfmKG: scan.bfmKG,
            pbf: scan.pbf,
            inbodyScore: scan.inbodyScore,
            vfaCM2: scan.vfaCM2,
            notes: scan.notes
        )
        try database.upsertInBodyScan(persisted)
    }

    func deleteInBodyScan(scanDate: String) throws {
        let database = try openDatabase()
        try database.deleteInBodyScan(scanDate: scanDate)
    }
}

private extension LiveAppGateway {
    static let dayHeaderRegex = try! NSRegularExpression(pattern: "^##\\s+(.+)$", options: [])
    static let exerciseHeaderRegex = try! NSRegularExpression(pattern: "^###\\s+([A-Z]\\d+)\\.\\s+(.+)$", options: [.caseInsensitive])
    static let prescriptionRegex = try! NSRegularExpression(pattern: "^-\\s*(\\d+)\\s*x\\s*(.+?)\\s*@\\s*(.+)$", options: [.caseInsensitive])
    static let prescriptionRepsUnitRegex = try! NSRegularExpression(
        pattern: "\\b(reps?|seconds?|secs?|minutes?|mins?|meters?|miles?)\\b",
        options: [.caseInsensitive]
    )
    static let numericTokenRegex = try! NSRegularExpression(pattern: "[-+]?\\d+(?:\\.\\d+)?", options: [])
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
        if !Self.isValidSpreadsheetID(sheet) {
            throw LiveGatewayError.invalidSpreadsheetID
        }
        return config
    }

    func requireSheetsSetup() throws -> NativeAppConfiguration {
        let config = configStore.load()
        let sheet = config.spreadsheetID.trimmingCharacters(in: .whitespacesAndNewlines)
        if sheet.isEmpty {
            throw LiveGatewayError.missingSpreadsheetID
        }
        if !Self.isValidSpreadsheetID(sheet) {
            throw LiveGatewayError.invalidSpreadsheetID
        }
        return config
    }

    static func isValidSpreadsheetID(_ value: String) -> Bool {
        // Google Spreadsheet IDs are typically 44 characters of alphanumeric, hyphens, and underscores.
        let pattern = #"^[A-Za-z0-9_-]{20,}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    func loadOneRepMaxesFromConfig() -> [String: Double] {
        let config = configStore.load()
        var result: [String: Double] = [:]
        for (lift, entry) in config.oneRepMaxes where entry.valueKG >= 20 {
            result[lift] = entry.valueKG
        }
        return result
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

    func sanitizedSheetReferenceDate(_ referenceDate: Date) -> (date: Date, wasSanitized: Bool) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = nowProvider()
        let currentYear = calendar.component(.year, from: now)
        let referenceYear = calendar.component(.year, from: referenceDate)
        let yearDelta = abs(referenceYear - currentYear)
        if yearDelta > 2 {
            return (now, true)
        }
        return (referenceDate, false)
    }

    func weeklySheetName(referenceDate: Date) -> String {
        let safeReference = sanitizedSheetReferenceDate(referenceDate).date
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: safeReference)
        // On weekends (Sat=7, Sun=1) we're planning ahead — advance to next week's Monday.
        // On Mon–Fri, back up to this week's Monday.
        let rawOffset = (weekday + 5) % 7  // 0=Mon, 1=Tue, …, 5=Sat, 6=Sun
        let mondayOffset = (weekday == 7 || weekday == 1) ? (7 - rawOffset) : -rawOffset
        let monday = calendar.date(byAdding: .day, value: mondayOffset, to: safeReference) ?? safeReference
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
        progressionDirectivesBlock: String,
        oneRepMaxes: [String: Double] = [:]
    ) -> String {
        let oneRMSection: String
        if oneRepMaxes.isEmpty {
            oneRMSection = "ATHLETE 1RM PROFILE:\nNo 1RM data provided. Use RPE feedback from recent logs to infer appropriate intensity."
        } else {
            let lines = oneRepMaxes.sorted(by: { $0.key < $1.key }).map { exercise, value in
                String(format: "- %@: %.1f kg", exercise, value)
            }
            oneRMSection = "ATHLETE 1RM PROFILE (use these for percentage-based load calculations):\n" + lines.joined(separator: "\n")
        }

        return """
        You are an expert strength and conditioning coach creating a personalized weekly workout plan.

        CRITICAL: NO RANGES - use single values only (e.g., "15 reps" not "12-15", "24 kg" not "22-26 kg")

        \(oneRMSection)

        \(fortContext)

        RECENT WORKOUT HISTORY (LOCAL DB CONTEXT):
        \(dbContext)

        \(progressionDirectivesBlock)

        LOAD CALCULATION RULE:
        - Training max override: if Fort coach notes define a "training max" or "working max" (e.g., "use 90% of your 1RM as training max"), apply that definition first, then calculate all set percentages from that training max — not from the raw 1RM.
        - Load rounding: barbell lifts → nearest 0.5 kg; DB loads → nearest even 2 kg step.

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

        CYCLE STATUS: \(input.isNewCycle ? "NEW CYCLE START" : "MID-CYCLE")
        \(input.isNewCycle ? """
        This is Week 1 of a new 4-week Fort cycle. The Fort exercises have changed.
        SUPPLEMENTAL DAYS (Tue/Thu/Sat): This is a CLEAN SLATE. Select a completely fresh set of upper-body exercises — do NOT carry over exercises from the prior cycle. Choose new movements that complement the new Fort structure and the athlete's aesthetic goals.
        Any PROGRESS / HOLD_LOCK / NEUTRAL directives in the context below reflect the PREVIOUS cycle. They are provided for load-reference only. They must NOT be used to lock in prior exercise choices or constrain which exercises you select. Prior-cycle progression signals do not override the clean-slate requirement.
        """ : """
        This is a mid-cycle week. Keep the same supplemental exercises as prior weeks unless a progression directive explicitly requires a swap.
        Apply PROGRESS / HOLD_LOCK / NEUTRAL signals from prior logs.
        """)

        SUPPLEMENTAL SELECTION GOAL:
        Supplemental days (Tue/Thu/Sat) exist for one purpose: maximum aesthetic impact on the upper body, without impairing Fort performance. This is the primary selection criterion — not variety for its own sake, not general fitness. Choose exercises that maximally develop the following, in priority order:
          1. Arms — biceps shape + triceps fullness (HIGH priority)
          2. Delts — medial delt cap for shoulder width, rear delt for 3D look (HIGH priority)
          3. Upper chest — clavicular pec "pop" via incline pressing and fly patterns (HIGH priority)
          4. Back detail — upper-back density, rear-delt tie-in, posture (HIGH priority)
        Favour isolation and cable/DB work that directly targets these groups. Avoid exercise drift into general conditioning or functional patterns that don't serve the aesthetic priority list. Stimulus-efficient hypertrophy only — no junk volume.

        INTERFERENCE PROTECTION (non-negotiable):
        - Tuesday: protect Wednesday bench — no heavy chest/triceps/front-delt loading, no barbell pressing.
        - Thursday: protect Friday deadlift — no loaded carries, no heavy rows, no heavy biceps (>6 hard sets), no grip-fatiguing work.
        - Saturday: protect Monday squat and overall recovery — no heavy lower back, no spinal fatigue, no junk volume.
        - THAW conditioning: THAW intensity must not compromise next-day Fort performance. Even low-load conditioning (walking intervals, bike) should not push into fatigue that blunts Tuesday's or Wednesday's training. This is a fatigue management constraint, not just a format rule.
        - Delt carry-over: If Monday Fort already included DB Lateral Raises, Tuesday must default to rear-delt / scapular hygiene work (e.g., Face Pull, Cable Y-Raise, Reverse Pec Deck, Rear Delt Fly) instead of lateral raise patterns. This protects Wednesday bench performance and avoids redundant medial-delt fatigue.

        CORE PRINCIPLES:
        - Supplemental days (Tue/Thu/Sat) are ALL strictly upper body. Program biceps, triceps, shoulders (lateral raises, rear delts, face pulls, Y-raises), upper chest (incline press), and upper back (rows, cable work). This applies equally to Tuesday, Thursday, and Saturday — there is no lower body supplemental day.
        - NEVER program lower body exercises on supplemental days. This ban includes: squats, deadlifts, Romanian deadlifts, hip hinges, kettlebell swings, hyperextensions, back extensions, leg press, lunges, leg curls, or any lower-body-dominant movement. Lower body work belongs exclusively to Fort days (Mon/Wed/Fri).
        - Supplemental days must be substantive: minimum 5 exercises on each of Tue, Thu, and Sat.
        - Every supplemental day (Tue, Thu, Sat) MUST include McGill Big-3 (curl-up, side bridge, bird-dog). Label it as one block entry "McGill Big-3" with coaching cues in the Notes field.
        - No exercise repeated across supplemental days within the same week. Tuesday, Thursday, and Saturday must each have a completely distinct, non-overlapping exercise selection. If you use Incline DB Press on Tuesday, do not use it on Thursday or Saturday.
        - Preserve explicit keep/stay-here progression constraints from prior logs.
        - Never increase both reps and load in the same week for the same exercise.
        - Notes must be clean coaching cues only: max 2 short sentences, execution-focused. Never include load calculations (e.g. "40% of 1RM = X kg"), percentage references, internal reasoning, or directive references.

        MANDATORY HARD RULES:
        - Equipment: No belt on pulls, standing calves only. No split squats on supplemental days (Tue/Thu/Sat). Fort-trainer-programmed split squats on Mon/Wed/Fri are permitted and must not be swapped.
        - Dumbbells: even-number loads only (no odd DB loads except main barbell lifts).
        - Biceps: rotate grips (supinated -> neutral -> pronated), no repeated adjacent supplemental-day grip.
        - Triceps: vary attachments across Tue/Thu/Sat. Fort Friday triceps: prefer straight-bar attachment with heavier loading (strength-emphasis day). No single-arm D-handle triceps on Saturday.
        - Carries: Tuesday only; use kettlebells exclusively — never dumbbells — to protect Friday deadlift grip.
        - Conditioning (THAW blocks): Sets = 1, Reps = total block duration (e.g. "12 min"), Load = 0. All interval structure, distances, pace targets, and effort cues go in Notes only. Example — correct: Reps = "12 min", Notes = "8 × 300m at tempo; 30 sec easy recovery between." Incorrect: Sets = 8, Reps = 300.
        - Canonical log format in sheets: performance | RPE x | Notes: ...

        OUTPUT REQUIREMENTS:
        - Use ## day headers and ### block.exercise headers.
        - Include six training days (Mon-Sat). Sunday is always complete rest — do not generate a Sunday block.
        - Keep A:H sheet compatibility (Block, Exercise, Sets, Reps, Load, Rest, Notes, Log).
        - American spelling.
        - Exercise names: Title Case only. Never use ALL CAPS for exercise names. Write "Pull Up" not "PULL UP", "Incline DB Press" not "INCLINE DB PRESS", "Barbell RDL" not "BARBELL RDL". Abbreviations (DB, KB, RDL, etc.) stay abbreviated but are not full caps of the entire name.
        - Notes: maximum 1-2 concise coaching cues per exercise (1 sentence each). Do not reproduce lengthy program descriptions or background context. Focus on execution — what the athlete should feel or do differently.
        - Sparse history rule: for Fort aux exercises with fewer than 2 logged sessions, infer an appropriate starting load from the athlete's overall strength profile, similar exercise history, the prescribed rep range, and a target RPE of 7-8. Use intelligent inference — not a fixed percentage formula.
        - Sauna: include a sauna block at the end of each training day (Mon-Sat) where contextually appropriate. Format it as a single block entry (e.g., "G1. Sauna") with a short duration note.
        """
    }

    func buildCorrectionPrompt(
        plan: String,
        unresolvedViolations: [any ViolationDescribing],
        fortCompilerContext: String,
        fortFidelitySummary: String
    ) -> String {
        let rendered = unresolvedViolations.prefix(20).map { violation -> String in
            "- \(violation.code) | \(violation.day) | \(violation.exercise) | \(violation.message)"
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
        - Each supplemental day (Tue, Thu, Sat) must have at least 5 exercises.
        - Each supplemental day must include McGill Big-3 (curl-up, side bridge, bird-dog).

        Return ONLY the full corrected plan in the same markdown format, starting directly with the first markdown header (# or ##).
        Do not include analysis, reasoning, preamble, or any text before the plan markdown.

        PLAN:
        \(plan)
        """
    }

    func loadPriorSupplementalForProgression(config: NativeAppConfiguration) async throws -> [String: [PriorSupplementalExercise]] {
        guard let sheetsClient = try? await makeSheetsClient(config: config) else {
            return [:]
        }

        let sheetNames = try await sheetsClient.fetchSheetNames()
        guard let preferredSheet = preferredWeeklyPlanSheetName(sheetNames) else {
            return [:]
        }

        let values = try await sheetsClient.readSheetAtoH(sheetName: preferredSheet)
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

    // MARK: - Two-Pass Generation Helpers

    /// Build a short prompt asking Claude to list only the exercise names it plans to use
    /// on the three supplemental days (Tue/Thu/Sat). No sets, reps, or loads needed —
    /// just names so we can pull targeted DB history before Pass 2.
    func buildExerciseSelectionPrompt(input: PlanGenerationInput, fortContext: String) -> String {
        let cycleBlock = input.isNewCycle
            ? "NEW CYCLE: Select a completely fresh set of exercises — do NOT repeat prior-cycle choices."
            : "MID-CYCLE: Keep exercises consistent with prior weeks unless progression requires a swap."

        return """
        You are selecting supplemental exercises for Tue/Thu/Sat workout days.

        ATHLETE: Samuel Light | kg | Aesthetic hypertrophy focus
        SCHEDULE: Fort Mon/Wed/Fri | Supplemental Tue/Thu/Sat

        AESTHETIC PRIORITY ORDER (supplemental volume purpose):
          1. Arms — biceps shape + triceps fullness (HIGH priority)
          2. Delts — medial delt cap for width, rear delt for 3D look (HIGH priority)
          3. Upper chest — clavicular pec "pop" via incline pressing/fly patterns (HIGH priority)
          4. Back detail — upper-back density, rear-delt tie-in, posture (HIGH priority)

        FORT CONTEXT (Mon/Wed/Fri exercises already programmed):
        \(fortContext)

        \(cycleBlock)

        INTERFERENCE RULES:
        - Tuesday: no heavy chest/triceps/front-delt loading; protect Wednesday bench.
        - Thursday: no loaded carries, no heavy rows, no heavy biceps (>6 hard sets); protect Friday deadlift grip.
        - Saturday: upper body only; no heavy lower back; protect Monday squat.

        HARD RULES:
        - No split squats on supplemental days.
        - Standing calves only (never seated).
        - Biceps: rotate grips across Tue/Thu/Sat — supinated -> neutral -> pronated; never same grip on consecutive days.
        - Triceps: vary attachments across Tue/Thu/Sat (rope on Tue, straight-bar variant on Thu/Sat, no single-arm D-handle on Sat).
        - No same exercise repeated on two supplemental days in the same week.
        - Carries: Tuesday only, KB exclusively.
        - Every supplemental day must include McGill Big-3 (curl-up, side bridge, bird-dog) and an incline walk.
        - Minimum 5 exercises per supplemental day.

        TASK: List the exercise names you plan to use for Tuesday, Thursday, and Saturday.
        Include ALL exercises (McGill Big-3 warm-up, main hypertrophy work, isolation, incline walk).
        Apply all interference and hard rules above.

        Return ONLY a plain-text list in this exact format — no explanation, no sets, no reps, no markdown:
        Tuesday: Exercise A, Exercise B, Exercise C
        Thursday: Exercise D, Exercise E, Exercise F
        Saturday: Exercise G, Exercise H, Exercise I
        """
    }

    /// Parse the Pass 1 response into a dict keyed by uppercase day name.
    /// Returns an empty dict on parse failure so the caller can fall back gracefully.
    func parseSelectedExercises(from text: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        let dayKeys = ["TUESDAY", "THURSDAY", "SATURDAY"]

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            // Match "Tuesday: ...", "thursday: ...", etc.
            guard let colonRange = trimmed.range(of: ":") else {
                continue
            }
            let dayRaw = String(trimmed[..<colonRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard dayKeys.contains(dayRaw) else {
                continue
            }

            let exercisePart = String(trimmed[colonRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if exercisePart.isEmpty {
                continue
            }

            let exercises = exercisePart
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if !exercises.isEmpty {
                result[dayRaw] = exercises
            }
        }

        // Only return a result if all three days parsed successfully.
        let allParsed = dayKeys.allSatisfy { result[$0] != nil && !(result[$0]!.isEmpty) }
        return allParsed ? result : [:]
    }

    /// Build targeted DB context for ONLY the exercises selected in Pass 1.
    /// Mirrors the Python `build_targeted_db_context()` logic.
    /// Returns nil if no targeted history is found (caller should fall back to generic context).
    func buildTargetedDBContext(
        for selectedExercises: [String: [String]],
        maxChars: Int = 3200,
        logsPerExercise: Int = 4
    ) -> String? {
        guard let database = try? openDatabase() else {
            return nil
        }

        // Collect all exercise names across all three supplemental days, deduplicated.
        let allNames = Array(Set(selectedExercises.values.flatMap { $0 }))
        guard !allNames.isEmpty else {
            return nil
        }

        let normalizer = getNormalizer()

        // Build a deduplicated list of (displayName, normalizedKey) pairs.
        var seen = Set<String>()
        var targets: [(displayName: String, normalizedKey: String)] = []
        for name in allNames {
            let norm = normalizer.canonicalKey(name)
            guard !norm.isEmpty, !seen.contains(norm) else {
                continue
            }
            seen.insert(norm)
            targets.append((displayName: normalizer.canonicalName(name), normalizedKey: norm))
        }

        guard !targets.isEmpty else {
            return nil
        }

        // Fetch logs for just these exercises.
        let normalizedKeys = targets.map { $0.normalizedKey }
        guard let rows = try? database.fetchTargetedLogContextRows(
            normalizedNames: normalizedKeys,
            logsPerExercise: logsPerExercise
        ), !rows.isEmpty else {
            return nil
        }

        // Group rows by normalizedKey so we can emit one block per exercise.
        var rowsByNorm: [String: [PersistedTargetedLogContextRow]] = [:]
        for row in rows {
            rowsByNorm[row.normalizedName, default: []].append(row)
        }

        // Build global DB summary header line.
        let dbSummaryLine: String
        if let summary = try? database.countSummary() {
            let logCount = summary.exerciseLogs
            let rpeCount = summary.logsWithRPE
            let rpePct = logCount > 0 ? (Double(rpeCount) / Double(logCount) * 100) : 0.0
            dbSummaryLine = "\(summary.exercises) exercises | \(summary.sessions) sessions | \(logCount) logs | RPE coverage \(String(format: "%.1f", rpePct))%"
        } else {
            dbSummaryLine = "DB summary unavailable."
        }

        var lines: [String] = [
            "EXERCISE HISTORY FROM DATABASE:",
            "- DB: \(dbSummaryLine).",
            "- Recent prescription + performance data for selected exercises:",
        ]

        func fitsBudget(_ candidate: [String]) -> Bool {
            return maxChars <= 0 || candidate.joined(separator: "\n").count <= maxChars
        }

        var added = 0
        for (displayName, normalizedKey) in targets {
            guard let exerciseRows = rowsByNorm[normalizedKey], !exerciseRows.isEmpty else {
                continue
            }

            let compactEntries: [String] = exerciseRows.map { row in
                let dayOrDate = row.sessionDateISO.isEmpty ? row.dayLabel : row.sessionDateISO
                var rx = ""
                if !row.sets.isEmpty && !row.reps.isEmpty {
                    rx = "\(row.sets)x\(row.reps)"
                    if !row.load.isEmpty {
                        rx += " @\(row.load)"
                    }
                } else if !row.load.isEmpty {
                    rx = "@\(row.load)"
                }

                var logPart = String(row.logText.prefix(70))
                if let rpe = row.parsedRPE, !row.logText.lowercased().contains("rpe") {
                    let rpeStr = rpe.truncatingRemainder(dividingBy: 1) == 0
                        ? String(format: "%.0f", rpe)
                        : String(format: "%.1f", rpe)
                    logPart = logPart.isEmpty ? "RPE \(rpeStr)" : "\(logPart) | RPE \(rpeStr)"
                }

                var entry = "\(dayOrDate): \(rx)"
                if !logPart.isEmpty {
                    entry += " [\(logPart)]"
                }
                return entry
            }

            let candidateLine = "  - [DB] \(displayName) -> " + compactEntries.joined(separator: " || ")
            let candidateLines = lines + [candidateLine]
            if !fitsBudget(candidateLines) {
                lines.append("- Context truncated to stay within prompt budget.")
                break
            }

            lines.append(candidateLine)
            added += 1
        }

        if added == 0 {
            return nil
        }

        let tail = "- Use this for load/rep reference; prior-week sheet remains primary for immediate progression."
        if fitsBudget(lines + [tail]) {
            lines.append(tail)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Generic DB Context (fallback)

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

    /// Strip any reasoning preamble Claude may have emitted before the plan begins.
    /// Keeps everything from the first `# ` or `## ` header onward.
    func stripPlanPreamble(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") {
                return lines[index...].joined(separator: "\n")
            }
        }
        return text
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

        let datedCandidates = planFiles.compactMap { url -> (URL, Date)? in
            guard let date = Self.parseLocalPlanDate(from: url.lastPathComponent) else {
                return nil
            }
            return (url, date)
        }

        if let preferredLocal = Self.preferredCandidate(
            datedCandidates,
            referenceDate: nowProvider(),
            nearWindowDays: 35,
            fallbackToMostRecent: false
        )?.0 {
            let text = try String(contentsOf: preferredLocal, encoding: .utf8)
            let days = markdownDaysToPlanDays(planText: text, source: .localCache)
            return PlanSnapshot(
                title: normalizedPlanTitle(preferredLocal.lastPathComponent),
                source: .localCache,
                days: days,
                summary: normalizedPlanSummary("Loaded from local markdown artifact.")
            )
        }

        let sorted = planFiles.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
        guard datedCandidates.isEmpty, let latest = sorted.first else {
            throw LiveGatewayError.noPlanData
        }

        let text = try String(contentsOf: latest, encoding: .utf8)
        let days = markdownDaysToPlanDays(planText: text, source: .localCache)
        return PlanSnapshot(
            title: normalizedPlanTitle(latest.lastPathComponent),
            source: .localCache,
            days: days,
            summary: normalizedPlanSummary("Loaded from local markdown artifact.")
        )
    }

    func localPlanFileName(for sheetName: String) -> String {
        let slug = sheetName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "workout_plan_\(slug).md"
    }

    func preferredWeeklyPlanSheetName(_ sheetNames: [String]) -> String? {
        Self.preferredWeeklyPlanSheetName(sheetNames, referenceDate: nowProvider())
    }

    static func preferredWeeklyPlanSheetName(_ sheetNames: [String], referenceDate: Date) -> String? {
        let candidates = sheetNames.compactMap { name -> (String, Date)? in
            guard let date = GoogleSheetsClient.parseWeeklyPlanSheetDate(name) else {
                return nil
            }
            return (name, date)
        }

        return preferredCandidate(
            candidates,
            referenceDate: referenceDate,
            nearWindowDays: 35,
            fallbackToMostRecent: true
        )?.0
    }

    static func parseLocalPlanDate(from fileName: String) -> Date? {
        let pattern = #"^workout_plan_weekly_plan_(\d{1,2})_(\d{1,2})_(\d{4})\.md$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: fileName, range: NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)),
              let monthRange = Range(match.range(at: 1), in: fileName),
              let dayRange = Range(match.range(at: 2), in: fileName),
              let yearRange = Range(match.range(at: 3), in: fileName),
              let month = Int(fileName[monthRange]),
              let day = Int(fileName[dayRange]),
              let year = Int(fileName[yearRange])
        else {
            return nil
        }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date
    }

    static func preferredCandidate<T>(
        _ candidates: [(T, Date)],
        referenceDate: Date,
        nearWindowDays: Int,
        fallbackToMostRecent: Bool
    ) -> (T, Date)? {
        guard !candidates.isEmpty else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let maxDistance = TimeInterval(nearWindowDays * 86_400)

        let scored = candidates.map { candidate -> (T, Date, TimeInterval, Bool) in
            let candidateDay = calendar.startOfDay(for: candidate.1)
            let distance = abs(candidateDay.timeIntervalSince(referenceDay))
            let isFutureOrToday = candidateDay >= referenceDay
            return (candidate.0, candidate.1, distance, isFutureOrToday)
        }

        let nearby = scored.filter { $0.2 <= maxDistance }
        if let preferred = nearby.sorted(by: { lhs, rhs in
            if lhs.2 != rhs.2 {
                return lhs.2 < rhs.2
            }
            if lhs.3 != rhs.3 {
                return lhs.3 && !rhs.3
            }
            return lhs.1 > rhs.1
        }).first {
            return (preferred.0, preferred.1)
        }

        guard fallbackToMostRecent else {
            return nil
        }

        return candidates.sorted(by: { $0.1 < $1.1 }).last
    }

    /// Parse the generated markdown text for a single day into the 8-column sheet schema.
    ///
    /// Each returned row is `[Block, Exercise, Sets, Reps, Load, Rest, Notes, Log]`.
    /// The Log column is always empty — the user fills that in after the workout.
    ///
    /// - Parameters:
    ///   - planText: The raw markdown for one day (may include the `## DAY` header or start directly
    ///               with exercise blocks — either form is accepted).
    ///   - dayLabel: A label used only for context when planText contains no `## DAY` header.
    ///               When planText does contain a header the header's label is used.
    /// - Returns: An array of 8-element string arrays, one per exercise (no header row).
    func parsePlanToSheetRows(planText: String, dayLabel: String) -> [[String]] {
        // Parse line by line. Skip day headers, blank lines, and non-exercise lines.
        // Only `### Xn. Exercise Name` blocks produce rows.
        let lines = planText.components(separatedBy: .newlines)
        var rows: [[String]] = []

        var currentBlock = ""
        var currentExercise = ""
        var currentSets = ""
        var currentReps = ""
        var currentLoad = ""
        var currentRest = ""
        var currentNotes = ""
        var inExercise = false

        func flushExercise() {
            guard inExercise, !currentExercise.isEmpty else { return }
            rows.append(GoogleSheetsClient.enforceEightColumnSchema([
                currentBlock, currentExercise, currentSets, currentReps,
                currentLoad, currentRest, currentNotes,
                "",   // Log — always empty at generation time; user fills in after the workout
            ]))
            currentBlock = ""; currentExercise = ""; currentSets = ""; currentReps = ""
            currentLoad = ""; currentRest = ""; currentNotes = ""
            inExercise = false
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            // Day headers (## MONDAY, ## TUESDAY, etc.) — skip
            if line.hasPrefix("## ") {
                continue
            }

            // Exercise header: ### A1. Exercise Name
            if let match = firstMatch(Self.exerciseHeaderRegex, text: line),
               let capturedBlock = match[0],
               let capturedExercise = match[1] {
                flushExercise()
                currentBlock = capturedBlock
                currentExercise = capturedExercise
                currentSets = ""; currentReps = ""; currentLoad = ""
                currentRest = ""; currentNotes = ""
                inExercise = true
                continue
            }

            guard inExercise else { continue }

            // Prescription line: - N x M @ Load kg
            if let parsed = parsePrescriptionLine(line) {
                currentSets = parsed.sets
                currentReps = parsed.reps
                currentLoad = parsed.load
                continue
            }

            // Rest line: - **Rest:** ...
            if line.lowercased().hasPrefix("- **rest:**") {
                currentRest = line
                    .replacingOccurrences(of: "- **Rest:**", with: "", options: [.caseInsensitive])
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            // Notes line: - **Notes:** ...
            if line.lowercased().hasPrefix("- **notes:**") {
                currentNotes = line
                    .replacingOccurrences(of: "- **Notes:**", with: "", options: [.caseInsensitive])
                    .trimmingCharacters(in: .whitespaces)
                continue
            }
        }

        flushExercise()
        return rows
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

        // Validation metadata is intentionally NOT written to the sheet —
        // it pollutes the sync data and creates noise rows in the exercise history.

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

                    if let parsed = parsePrescriptionLine(probe) {
                        sets = parsed.sets
                        reps = parsed.reps
                        load = parsed.load
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
            } else if lower.hasPrefix("note:") {
                notes = part.replacingOccurrences(of: "Note:", with: "", options: [.caseInsensitive]).trimmingCharacters(in: .whitespaces)
            } else if performance.isEmpty {
                performance = part
            }
        }

        return (performance, rpe, notes)
    }

    static func selectLoggerWorkout(workouts: [SheetDayWorkout], todayName: String) -> SheetDayWorkout? {
        if let todayNonEmpty = workouts.first(where: {
            $0.dayName.caseInsensitiveCompare(todayName) == .orderedSame && !$0.exercises.isEmpty
        }) {
            return todayNonEmpty
        }

        if let firstNonEmpty = workouts.first(where: { !$0.exercises.isEmpty }) {
            return firstNonEmpty
        }

        return workouts.first(where: { $0.dayName.caseInsensitiveCompare(todayName) == .orderedSame }) ?? workouts.first
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

    func parsePrescriptionLine(_ line: String) -> (sets: String, reps: String, load: String)? {
        guard let match = Self.prescriptionRegex.firstMatch(in: line, options: [], range: nsRange(line)),
              let setsRange = Range(match.range(at: 1), in: line),
              let repsRange = Range(match.range(at: 2), in: line),
              let loadRange = Range(match.range(at: 3), in: line)
        else {
            return nil
        }

        let sets = String(line[setsRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let repsRaw = String(line[repsRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let loadRaw = String(line[loadRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        let repsSansUnits = Self.prescriptionRepsUnitRegex.stringByReplacingMatches(
            in: repsRaw,
            options: [],
            range: nsRange(repsRaw),
            withTemplate: ""
        )
        let cleanedReps = repsSansUnits
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reps = cleanedReps.isEmpty ? repsRaw : cleanedReps

        let load: String
        if let loadMatch = Self.numericTokenRegex.firstMatch(in: loadRaw, options: [], range: nsRange(loadRaw)),
           let tokenRange = Range(loadMatch.range(at: 0), in: loadRaw) {
            load = String(loadRaw[tokenRange])
        } else {
            load = loadRaw
        }

        return (sets, reps, load)
    }

    func normalizedPlanTitle(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizedPlanSummary(_ raw: String) -> String {
        normalizedPlanTitle(raw)
    }
}

extension LiveAppGateway {
    static func testPreferredWeeklyPlanSheetName(_ sheetNames: [String], referenceDate: Date) -> String? {
        preferredWeeklyPlanSheetName(sheetNames, referenceDate: referenceDate)
    }

    static func testPreferredCandidate(
        _ candidates: [(String, Date)],
        referenceDate: Date,
        nearWindowDays: Int,
        fallbackToMostRecent: Bool
    ) -> (String, Date)? {
        preferredCandidate(
            candidates,
            referenceDate: referenceDate,
            nearWindowDays: nearWindowDays,
            fallbackToMostRecent: fallbackToMostRecent
        )
    }

    static func testParseLocalPlanDate(from fileName: String) -> Date? {
        parseLocalPlanDate(from: fileName)
    }

    static func testParseExistingLog(_ raw: String) -> (String, String, String) {
        let parsed = parseExistingLog(raw)
        return (parsed.performance, parsed.rpe, parsed.notes)
    }

    static func testSelectLoggerWorkout(_ workouts: [SheetDayWorkout], todayName: String) -> SheetDayWorkout? {
        selectLoggerWorkout(workouts: workouts, todayName: todayName)
    }

    static func testSanitizedSheetReferenceDate(referenceDate: Date, nowDate: Date) -> (Date, Bool) {
        let gateway = LiveAppGateway(nowProvider: { nowDate }, planWriteMode: .localOnly)
        let result = gateway.sanitizedSheetReferenceDate(referenceDate)
        return (result.date, result.wasSanitized)
    }

    static func testMarkdownDaysToPlanDays(_ planText: String) -> [PlanDayDetail] {
        let gateway = LiveAppGateway(planWriteMode: .localOnly)
        return gateway.markdownDaysToPlanDays(planText: planText, source: .localCache)
    }

    static func testParsePlanToSheetRows(planText: String, dayLabel: String) -> [[String]] {
        let gateway = LiveAppGateway(planWriteMode: .localOnly)
        return gateway.parsePlanToSheetRows(planText: planText, dayLabel: dayLabel)
    }

    static func testParseSelectedExercises(from text: String) -> [String: [String]] {
        let gateway = LiveAppGateway(planWriteMode: .localOnly)
        return gateway.parseSelectedExercises(from: text)
    }
}
