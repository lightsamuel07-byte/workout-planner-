import Foundation
import Combine

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var route: AppRoute
    @Published var setupState = SetupState()
    @Published var isSetupComplete = false
    @Published var setupErrors: [String] = []
    @Published var unlockInput = ""
    @Published var unlockError = ""
    @Published var isUnlocked = false

    @Published var generationInput = PlanGenerationInput()
    @Published var generationStatus = ""
    @Published var isGenerating = false
    @Published var planSnapshot = PlanSnapshot.empty
    @Published var selectedPlanDay = ""
    @Published var viewPlanError = ""
    @Published var loggerSession = LoggerSessionState.empty
    @Published var loggerStatus = ""
    @Published var progressSummary = ProgressSummary.empty
    @Published var weeklyReviewSummaries: [WeeklyReviewSummary] = []

    @Published var selectedHistoryExercise = "Reverse Pec Deck"
    @Published var exerciseCatalog: [String] = []
    @Published var isRebuildingDBCache = false
    @Published var dbRebuildSummary = ""

    @Published var planSearchQuery = ""
    @Published var showPlanNotes = true
    @Published var showPlanLogs = false
    @Published var showPlanLoggedOnly = false
    @Published var planBlockFilter = "All Blocks"
    @Published var loggerSearchQuery = ""
    @Published var showLoggerIncompleteOnly = false
    @Published var loggerBlockFilter = "All Blocks"
    @Published var weeklyReviewQuery = ""
    @Published var weeklyReviewSort: WeeklyReviewSortMode = .newest

    @Published var lastPlanRefreshAt: Date?
    @Published var lastLoggerRefreshAt: Date?
    @Published var lastAnalyticsRefreshAt: Date?
    @Published var lastDBRebuildAt: Date?

    @Published var topExercises: [TopExerciseSummary] = []
    @Published var recentSessions: [RecentSessionSummary] = []
    @Published var dbHealthSnapshot = DBHealthSnapshot.empty

    @Published var oneRepMaxFields: [OneRepMaxFieldState] = []
    @Published var oneRepMaxStatus = ""

    // TEMP: TEST HARNESS — REMOVE AFTER VERIFICATION
    @Published var testHarnessFortInput = ""
    @Published var testHarnessResult = APITestHarnessResult.empty
    @Published var testHarnessIsSending = false
    @Published var testHarnessShowPayload = false
    // END TEMP: TEST HARNESS

    private let gateway: NativeAppGateway
    private let configStore: AppConfigurationStore

    init(gateway: NativeAppGateway = InMemoryAppGateway(), configStore: AppConfigurationStore = FileAppConfigurationStore()) {
        self.gateway = gateway
        self.configStore = configStore
        self.route = gateway.initialRoute()
        restoreFromConfig()
        refreshAnalytics()
    }

    var dashboardDays: [DayPlanSummary] {
        gateway.loadDashboardDays()
    }

    var historyPoints: [ExerciseHistoryPoint] {
        gateway.loadExerciseHistory(exerciseName: selectedHistoryExercise)
    }

    var dbStatusText: String {
        gateway.dbStatusText()
    }

    var statusHeadline: String {
        let banner = statusBanner
        if banner.text.isEmpty {
            return "Ready"
        }
        switch banner.severity {
        case .info:
            return "Info"
        case .success:
            return "Success"
        case .warning:
            return "Attention"
        case .error:
            return "Action Required"
        }
    }

    var analyticsFreshnessText: String {
        guard let last = lastAnalyticsRefreshAt else {
            return "Analytics not refreshed yet."
        }
        let seconds = Int(Date().timeIntervalSince(last))
        if seconds < 60 {
            return "Analytics refreshed just now."
        }
        if seconds < 3_600 {
            return "Analytics refreshed \(seconds / 60)m ago."
        }
        return "Analytics refreshed \(seconds / 3_600)h ago."
    }

    var statusBanner: StatusBanner {
        if !viewPlanError.isEmpty {
            return StatusBanner(text: viewPlanError, severity: .error)
        }

        if !loggerStatus.isEmpty {
            return StatusBanner(text: loggerStatus, severity: severity(for: loggerStatus))
        }

        if !generationStatus.isEmpty {
            return StatusBanner(text: generationStatus, severity: severity(for: generationStatus))
        }

        if !unlockError.isEmpty {
            return StatusBanner(text: unlockError, severity: .error)
        }

        return .empty
    }

    var setupReadinessText: String {
        let errors = setupState.validate()
        if errors.isEmpty {
            return "Setup fields look complete."
        }
        return errors.joined(separator: " ")
    }

    var setupReadinessSeverity: StatusSeverity {
        setupState.validate().isEmpty ? .success : .warning
    }

    var setupChecklist: [SetupChecklistItem] {
        let keyReady = !normalizedWhitespace(setupState.anthropicAPIKey).isEmpty
        let sheetReady = !normalizedWhitespace(setupState.spreadsheetID).isEmpty
        let authHint = normalizedWhitespace(setupState.googleAuthHint)
        let authReady = !authHint.isEmpty && authHint.caseInsensitiveCompare("OAuth token path") != .orderedSame
        let unlockReady = true

        return [
            SetupChecklistItem(id: "anthropic_key", title: "Anthropic API key provided", isComplete: keyReady),
            SetupChecklistItem(id: "sheet_id", title: "Spreadsheet ID provided", isComplete: sheetReady),
            SetupChecklistItem(id: "google_auth", title: "Google auth hint provided", isComplete: authReady),
            SetupChecklistItem(id: "unlock", title: "Unlock preference configured", isComplete: unlockReady),
        ]
    }

    var setupCompletionPercent: Double {
        if setupChecklist.isEmpty {
            return 0
        }
        let completed = setupChecklist.filter(\.isComplete).count
        return (Double(completed) / Double(setupChecklist.count)) * 100
    }

    var setupMissingSummary: String {
        let missing = setupChecklist.filter { !$0.isComplete }.map(\.title)
        if missing.isEmpty {
            return "All required setup fields are complete."
        }
        return "Missing: \(missing.joined(separator: ", "))."
    }

    var mondayCharacterCount: Int {
        generationInput.monday.count
    }

    var wednesdayCharacterCount: Int {
        generationInput.wednesday.count
    }

    var fridayCharacterCount: Int {
        generationInput.friday.count
    }

    var canGenerateNow: Bool {
        generationReadinessReport.isReady && !isGenerating && setupState.validate().isEmpty
    }

    var generationDisabledReason: String {
        if isGenerating {
            return "Generation already in progress."
        }
        let setupErrors = setupState.validate()
        if !setupErrors.isEmpty {
            return setupErrors.joined(separator: " ")
        }
        return generationReadinessSummary == "Readiness checks passed." ? "" : generationReadinessSummary
    }

    var oneRepMaxWarningForGeneration: String {
        if oneRepMaxesAreFilled {
            return ""
        }
        let missing = oneRepMaxMissingLifts.joined(separator: ", ")
        return "1RM values not set for: \(missing). Go to Settings to enter them. Generation will proceed but percentage-based loads may be inaccurate."
    }

    var generationReadinessReport: GenerationReadinessReport {
        let rows: [(name: String, header: String, text: String)] = [
            ("Monday", "MONDAY", generationInput.monday),
            ("Wednesday", "WEDNESDAY", generationInput.wednesday),
            ("Friday", "FRIDAY", generationInput.friday),
        ]

        let missingDays: [String] = rows.compactMap { row -> String? in
            normalizedWhitespace(row.text).isEmpty ? row.name : nil
        }

        let missingHeaders: [String] = rows.compactMap { row -> String? in
            let upper = row.text.uppercased()
            if normalizedWhitespace(row.text).isEmpty {
                return nil
            }
            return upper.contains(row.header) ? nil : row.name
        }

        let lowSignalDays: [String] = rows.compactMap { row -> String? in
            let signalCount = nonEmptyLineCount(row.text)
            if normalizedWhitespace(row.text).isEmpty {
                return nil
            }
            return signalCount < 3 ? row.name : nil
        }

        let normalizedRows = rows.map { row in
            (
                name: row.name,
                value: normalizedWhitespace(row.text).lowercased()
            )
        }
        var duplicates: [String] = []
        for leftIndex in normalizedRows.indices {
            for rightIndex in normalizedRows.indices where rightIndex > leftIndex {
                let left = normalizedRows[leftIndex]
                let right = normalizedRows[rightIndex]
                if left.value.isEmpty || right.value.isEmpty {
                    continue
                }
                if left.value == right.value {
                    duplicates.append("Inputs for \(left.name) and \(right.name) are identical.")
                }
            }
        }

        return GenerationReadinessReport(
            missingDays: missingDays,
            missingHeaders: missingHeaders,
            lowSignalDays: lowSignalDays,
            duplicatedDayPairs: duplicates
        )
    }

    var generationReadinessSummary: String {
        generationReadinessReport.summary
    }

    var generationReadinessSeverity: StatusSeverity {
        let report = generationReadinessReport
        if report.isReady {
            return .success
        }
        if !report.missingDays.isEmpty {
            return .error
        }
        return .warning
    }

    var generationHasPotentialDuplication: Bool {
        !generationReadinessReport.duplicatedDayPairs.isEmpty
    }

    var generationIssueCount: Int {
        generationReadinessReport.issues.count
    }

    var generationInputFingerprint: String {
        let payload = [
            normalizedMultiline(generationInput.monday),
            normalizedMultiline(generationInput.wednesday),
            normalizedMultiline(generationInput.friday),
        ].joined(separator: "\n--\n")
        return stableDigest(payload)
    }

    var generationDayLineCounts: [String: Int] {
        [
            "Monday": nonEmptyLineCount(generationInput.monday),
            "Wednesday": nonEmptyLineCount(generationInput.wednesday),
            "Friday": nonEmptyLineCount(generationInput.friday),
        ]
    }

    var generationTargetSheetName: String {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let mondayOffset = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: now) ?? now
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "M/d/yyyy"
        return "Weekly Plan (\(formatter.string(from: monday)))"
    }

    var filteredExerciseCatalog: [String] {
        let query = selectedHistoryExercise.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return Array(exerciseCatalog.prefix(24))
        }

        let prefixed = exerciseCatalog.filter { $0.lowercased().hasPrefix(query) }
        if !prefixed.isEmpty {
            return Array(prefixed.prefix(24))
        }

        let contained = exerciseCatalog.filter { $0.lowercased().contains(query) }
        return Array(contained.prefix(24))
    }

    var orderedPlanDays: [PlanDayDetail] {
        planSnapshot.days.sorted { lhs, rhs in
            let left = dayOrderIndex(dayLabel: lhs.dayLabel)
            let right = dayOrderIndex(dayLabel: rhs.dayLabel)
            if left != right {
                return left < right
            }
            return lhs.dayLabel.localizedCaseInsensitiveCompare(rhs.dayLabel) == .orderedAscending
        }
    }

    var selectedPlanDetail: PlanDayDetail? {
        if !selectedPlanDay.isEmpty,
           let match = orderedPlanDays.first(where: { $0.dayLabel == selectedPlanDay }) {
            return match
        }
        return orderedPlanDays.first
    }

    var selectedPlanDayPositionText: String {
        guard !orderedPlanDays.isEmpty,
              let selected = selectedPlanDetail,
              let index = orderedPlanDays.firstIndex(where: { $0.id == selected.id })
        else {
            return "Day 0 of 0"
        }
        return "Day \(index + 1) of \(orderedPlanDays.count)"
    }

    var filteredPlanExercises: [PlanExerciseRow] {
        guard let day = selectedPlanDetail else {
            return []
        }

        let query = normalizedWhitespace(planSearchQuery).lowercased()
        var rows = day.exercises

        if showPlanLoggedOnly {
            rows = rows.filter { !normalizedWhitespace($0.log).isEmpty }
        }

        let blockFilter = normalizedWhitespace(planBlockFilter)
        if !blockFilter.isEmpty, blockFilter != "All Blocks" {
            rows = rows.filter { normalizedWhitespace($0.block).caseInsensitiveCompare(blockFilter) == .orderedSame }
        }

        if !query.isEmpty {
            rows = rows.filter { row in
                [row.block, row.exercise, row.sets, row.reps, row.load, row.rest, row.notes, row.log]
                    .joined(separator: " ")
                    .lowercased()
                    .contains(query)
            }
        }

        return rows.sorted { lhs, rhs in
            if let left = lhs.sourceRow, let right = rhs.sourceRow, left != right {
                return left < right
            }
            return lhs.block.localizedCaseInsensitiveCompare(rhs.block) == .orderedAscending
        }
    }

    var planVisibleExerciseCount: Int {
        filteredPlanExercises.count
    }

    var planBlockCatalog: [String] {
        guard let day = selectedPlanDetail else {
            return ["All Blocks"]
        }
        let blocks = Set(
            day.exercises
                .map { normalizedWhitespace($0.block) }
                .filter { !$0.isEmpty }
        )
        return ["All Blocks"] + blocks.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var planDayCompletionCount: Int {
        filteredPlanExercises.filter { !normalizedWhitespace($0.log).isEmpty }.count
    }

    var planDayCompletionPercent: Double {
        if filteredPlanExercises.isEmpty {
            return 0
        }
        return (Double(planDayCompletionCount) / Double(filteredPlanExercises.count)) * 100
    }

    var planDayHasLogs: Bool {
        planDayCompletionCount > 0
    }

    var planDayCount: Int {
        orderedPlanDays.count
    }

    var planExerciseCount: Int {
        planSnapshot.days.reduce(0) { partial, day in
            partial + day.exercises.count
        }
    }

    var planDayStats: PlanDayStats {
        let rows = filteredPlanExercises
        if rows.isEmpty {
            return .empty
        }

        let blocks = Set(rows.map { $0.block }).count
        let volume = rows.reduce(0.0) { partial, row in
            partial + estimatedVolume(for: row)
        }

        return PlanDayStats(
            exerciseCount: rows.count,
            blockCount: blocks,
            estimatedVolumeKG: volume
        )
    }

    var loggerCompletionCount: Int {
        loggerSession.drafts.filter { isDraftComplete($0) }.count
    }

    var loggerTotalCount: Int {
        loggerSession.drafts.count
    }

    var loggerInvalidRPECount: Int {
        loggerSession.drafts.filter { draft in
            let trimmed = normalizedWhitespace(draft.rpe)
            return !trimmed.isEmpty && !isValidRPE(trimmed)
        }.count
    }

    var hasInvalidLoggerEntries: Bool {
        loggerInvalidRPECount > 0
    }

    var hasUnsavedLoggerChanges: Bool {
        loggerSession.drafts.contains { draft in
            !normalizedWhitespace(draft.performance).isEmpty ||
                !normalizedWhitespace(draft.rpe).isEmpty ||
                !normalizedWhitespace(draft.noteEntry).isEmpty
        }
    }

    var loggerCompletionPercent: Double {
        if loggerTotalCount == 0 {
            return 0
        }
        return (Double(loggerCompletionCount) / Double(loggerTotalCount)) * 100
    }

    var loggerVisibleCount: Int {
        loggerSession.drafts.filter { shouldShowDraft($0) }.count
    }

    var loggerPendingVisibleCount: Int {
        loggerSession.drafts.filter { shouldShowDraft($0) && !isDraftComplete($0) }.count
    }

    var loggerEditedCount: Int {
        loggerSession.drafts.filter { draft in
            !normalizedWhitespace(draft.performance).isEmpty ||
                !normalizedWhitespace(draft.rpe).isEmpty ||
                !normalizedWhitespace(draft.noteEntry).isEmpty
        }.count
    }

    var loggerNotesCount: Int {
        loggerSession.drafts.filter { !normalizedWhitespace($0.noteEntry).isEmpty }.count
    }

    var loggerSaveDisabledReason: String {
        if loggerSession.drafts.isEmpty {
            return "No exercises loaded for today."
        }
        if hasInvalidLoggerEntries {
            return "Fix invalid RPE values before saving (use 1-10)."
        }
        return ""
    }

    var loggerBlockCatalog: [String] {
        let blocks = Set(
            loggerSession.drafts
                .map { normalizedWhitespace($0.block) }
                .filter { !$0.isEmpty }
        )
        return ["All Blocks"] + blocks.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var loggerBlockProgressRows: [LoggerBlockProgress] {
        var grouped: [String: (completed: Int, total: Int)] = [:]
        for draft in loggerSession.drafts {
            let block = normalizedWhitespace(draft.block).isEmpty ? "Unspecified" : normalizedWhitespace(draft.block)
            var value = grouped[block] ?? (0, 0)
            value.total += 1
            if isDraftComplete(draft) {
                value.completed += 1
            }
            grouped[block] = value
        }

        return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { block in
            let value = grouped[block] ?? (0, 0)
            return LoggerBlockProgress(
                id: block.lowercased(),
                block: block,
                completed: value.completed,
                total: value.total
            )
        }
    }

    var filteredWeeklyReviewSummaries: [WeeklyReviewSummary] {
        var rows = weeklyReviewSummaries
        let query = normalizedWhitespace(weeklyReviewQuery).lowercased()
        if !query.isEmpty {
            rows = rows.filter { $0.sheetName.lowercased().contains(query) }
        }

        switch weeklyReviewSort {
        case .newest:
            rows.sort { $0.sheetName.localizedCaseInsensitiveCompare($1.sheetName) == .orderedDescending }
        case .highestCompletion:
            rows.sort { completionRate(of: $0) > completionRate(of: $1) }
        case .lowestCompletion:
            rows.sort { completionRate(of: $0) < completionRate(of: $1) }
        case .mostSessions:
            rows.sort { $0.sessions > $1.sessions }
        }

        return rows
    }

    var weeklyReviewAverageCompletion: Double {
        guard !weeklyReviewSummaries.isEmpty else {
            return 0
        }
        let total = weeklyReviewSummaries.reduce(0.0) { partial, row in
            partial + completionRate(of: row)
        }
        return total / Double(weeklyReviewSummaries.count)
    }

    var weeklyReviewBestWeek: WeeklyReviewSummary? {
        weeklyReviewSummaries.max { completionRate(of: $0) < completionRate(of: $1) }
    }

    var weeklyReviewWorstWeek: WeeklyReviewSummary? {
        weeklyReviewSummaries.min { completionRate(of: $0) < completionRate(of: $1) }
    }

    var dbRebuildDisabledReason: String {
        if isRebuildingDBCache {
            return "DB cache rebuild already in progress."
        }
        let sheetID = normalizedWhitespace(setupState.spreadsheetID)
        if sheetID.isEmpty {
            return "Setup required: spreadsheet ID is missing."
        }
        let authHint = normalizedWhitespace(setupState.googleAuthHint)
        if authHint.isEmpty || authHint.caseInsensitiveCompare("OAuth token path") == .orderedSame {
            return "Setup required: Google auth token path or bearer token is missing."
        }
        return ""
    }

    func dbWeekdayCompletionPercent(_ row: WeekdayCompletionSummary) -> Double {
        if row.totalRows == 0 {
            return 0
        }
        return (Double(row.loggedRows) / Double(row.totalRows)) * 100
    }

    var formattedDBRebuildSummaryLines: [String] {
        let raw = normalizedWhitespace(dbRebuildSummary)
        if raw.isEmpty {
            return []
        }
        let parts = raw
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                line.hasSuffix(".") ? line : "\(line)."
            }
        return parts
    }

    var exerciseHistorySummary: ExerciseHistorySummary {
        let points = historyPoints
        guard !points.isEmpty else {
            return .empty
        }

        let latest = points.first?.load ?? 0
        let maxLoad = points.map(\.load).max() ?? 0
        let oldest = points.last?.load ?? latest
        let delta = latest - oldest

        return ExerciseHistorySummary(
            entryCount: points.count,
            latestLoad: latest,
            maxLoad: maxLoad,
            loadDelta: delta,
            latestDateISO: points.first?.dateISO ?? ""
        )
    }

    var historyEmptyReason: String {
        if !historyPoints.isEmpty {
            return ""
        }
        let query = normalizedWhitespace(selectedHistoryExercise)
        if query.isEmpty {
            return "Type an exercise name or pick one from known exercises."
        }
        if filteredExerciseCatalog.isEmpty {
            return "No matching exercise found in catalog yet. Rebuild DB cache to import history."
        }
        return "No logged history for \"\(query)\" yet."
    }

    func completeSetup() {
        setupState = SetupState(
            anthropicAPIKey: normalizedWhitespace(setupState.anthropicAPIKey),
            spreadsheetID: normalizedWhitespace(setupState.spreadsheetID),
            googleAuthHint: normalizedWhitespace(setupState.googleAuthHint),
            localAppPassword: setupState.localAppPassword
        )

        let errors = setupState.validate()
        setupErrors = errors
        if errors.isEmpty {
            isSetupComplete = true
            unlockError = ""
            isUnlocked = setupState.localAppPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            persistConfig()
            generationStatus = "Setup saved. Ready to use live workflows."
            Task {
                await refreshPlanSnapshot()
                await refreshLoggerSession()
            }
            refreshAnalytics()
        }
    }

    func markSetupIncomplete() {
        isSetupComplete = false
        isUnlocked = false
        planSnapshot = .empty
        loggerSession = .empty
        loggerStatus = ""
    }

    func triggerReauth() {
        let hint = setupState.googleAuthHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if hint.isEmpty {
            generationStatus = "Re-auth flow requested. In Setup, set Google auth hint to your token.json path, then retry."
        } else {
            generationStatus = "Re-auth flow requested. Verify token at: \(hint)"
        }
    }

    func triggerRebuildDBCache() async {
        if isRebuildingDBCache {
            return
        }

        isRebuildingDBCache = true
        generationStatus = "Rebuilding DB cache from all weekly Google Sheets tabs..."
        dbRebuildSummary = ""
        defer { isRebuildingDBCache = false }

        do {
            let report = try await gateway.rebuildDatabaseCache()
            dbRebuildSummary = """
            Imported \(report.exerciseRowsImported) exercise rows across \(report.daySessionsImported) day sessions from \(report.weeklySheetsScanned) weekly sheets (\(report.loggedRowsImported) had logs).
            DB totals: \(report.dbExercises) exercises, \(report.dbSessions) sessions, \(report.dbExerciseLogs) rows.
            """
            generationStatus = "DB cache rebuild complete."
            lastDBRebuildAt = Date()
            refreshAnalytics()
            refreshExerciseCatalog()
        } catch {
            generationStatus = "DB cache rebuild failed: \(error.localizedDescription)"
        }
    }

    func unlock() {
        let required = setupState.localAppPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        if required.isEmpty {
            isUnlocked = true
            unlockError = ""
            return
        }

        if unlockInput == required {
            isUnlocked = true
            unlockError = ""
            unlockInput = ""
        } else {
            unlockError = "Incorrect app password."
        }
    }

    func runGeneration() async {
        let readiness = generationReadinessReport
        guard readiness.isReady else {
            generationStatus = readiness.summary
            return
        }

        guard setupState.validate().isEmpty else {
            generationStatus = "Setup is incomplete. Add Anthropic key and Spreadsheet ID first."
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        generationInput = PlanGenerationInput(
            monday: normalizedMultiline(generationInput.monday),
            wednesday: normalizedMultiline(generationInput.wednesday),
            friday: normalizedMultiline(generationInput.friday)
        )

        do {
            generationStatus = try await gateway.generatePlan(input: generationInput)
            await refreshPlanSnapshot()
            refreshAnalytics()
        } catch {
            generationStatus = "Generation failed: \(error.localizedDescription)"
        }
    }

    func refreshPlanSnapshot() async {
        do {
            let snapshot = try await gateway.loadPlanSnapshot()
            planSnapshot = snapshot
            viewPlanError = ""
            lastPlanRefreshAt = Date()
            if selectedPlanDay.isEmpty || !orderedPlanDays.contains(where: { $0.dayLabel == selectedPlanDay }) {
                selectedPlanDay = orderedPlanDays.first?.dayLabel ?? ""
            }
            if !planBlockCatalog.contains(planBlockFilter) {
                planBlockFilter = "All Blocks"
            }
        } catch {
            viewPlanError = "Unable to load plan: \(error.localizedDescription)"
            if planSnapshot.days.isEmpty {
                planSnapshot = .empty
            }
        }
    }

    func refreshLoggerSession() async {
        do {
            loggerSession = try await gateway.loadTodayLoggerSession()
            loggerStatus = ""
            lastLoggerRefreshAt = Date()
            if !loggerBlockCatalog.contains(loggerBlockFilter) {
                loggerBlockFilter = "All Blocks"
            }
        } catch {
            loggerStatus = "Unable to load workout logger: \(error.localizedDescription)"
            if loggerSession.drafts.isEmpty {
                loggerSession = .empty
            }
        }
    }

    func saveLoggerSession() async {
        if !loggerSaveDisabledReason.isEmpty {
            loggerStatus = "Failed to save logs: \(loggerSaveDisabledReason)"
            return
        }

        let sanitized = sanitizedLoggerSession(loggerSession)
        loggerSession = sanitized

        do {
            let summary = try await gateway.saveLoggerSession(sanitized)
            loggerStatus = "Saved logs. DB now has \(summary.exerciseLogs) log rows across \(summary.sessions) sessions."
            lastLoggerRefreshAt = Date()
            refreshAnalytics()
        } catch {
            loggerStatus = "Failed to save logs: \(error.localizedDescription)"
        }
    }

    func refreshAnalytics() {
        progressSummary = gateway.loadProgressSummary()
        weeklyReviewSummaries = gateway.loadWeeklyReviewSummaries()
        topExercises = gateway.loadTopExercises(limit: 5)
        recentSessions = gateway.loadRecentSessions(limit: 8)
        dbHealthSnapshot = gateway.loadDBHealthSnapshot()
        lastAnalyticsRefreshAt = Date()
        refreshExerciseCatalog()
    }

    func refreshExerciseCatalog() {
        exerciseCatalog = gateway.loadExerciseCatalog(limit: 240)
    }

    func applyHistorySuggestion(_ exerciseName: String) {
        selectedHistoryExercise = exerciseName
    }

    // MARK: - One Rep Max

    var oneRepMaxesAreFilled: Bool {
        let config = configStore.load()
        return NativeAppConfiguration.mainLifts.allSatisfy { lift in
            guard let entry = config.oneRepMaxes[lift] else { return false }
            return entry.valueKG >= 20 && entry.valueKG <= 300
        }
    }

    var oneRepMaxMissingLifts: [String] {
        let config = configStore.load()
        return NativeAppConfiguration.mainLifts.filter { lift in
            guard let entry = config.oneRepMaxes[lift] else { return true }
            return entry.valueKG < 20 || entry.valueKG > 300
        }
    }

    var oneRepMaxAllValid: Bool {
        oneRepMaxFields.allSatisfy(\.isValid)
    }

    var oneRepMaxHasChanges: Bool {
        let config = configStore.load()
        for field in oneRepMaxFields {
            guard let parsed = field.parsedValue else {
                if config.oneRepMaxes[field.liftName] != nil {
                    return true
                }
                continue
            }
            if let existing = config.oneRepMaxes[field.liftName] {
                if abs(existing.valueKG - parsed) > 0.01 {
                    return true
                }
            } else {
                return true
            }
        }
        return false
    }

    func loadOneRepMaxFields() {
        let config = configStore.load()
        oneRepMaxFields = NativeAppConfiguration.mainLifts.map { lift in
            let entry = config.oneRepMaxes[lift]
            let text: String
            if let entry, entry.valueKG >= 20 {
                text = String(format: "%.1f", entry.valueKG)
                    .replacingOccurrences(of: "\\.0$", with: "", options: .regularExpression)
            } else {
                text = ""
            }
            return OneRepMaxFieldState(
                id: lift,
                liftName: lift,
                inputText: text,
                lastUpdated: entry?.lastUpdated
            )
        }
    }

    func saveOneRepMaxes() {
        guard oneRepMaxAllValid else {
            oneRepMaxStatus = "Fix invalid values before saving."
            return
        }

        var config = configStore.load()
        let now = Date()
        for field in oneRepMaxFields {
            if let parsed = field.parsedValue {
                let existing = config.oneRepMaxes[field.liftName]
                let needsTimestampUpdate = existing == nil || abs((existing?.valueKG ?? 0) - parsed) > 0.01
                config.oneRepMaxes[field.liftName] = OneRepMaxEntry(
                    valueKG: parsed,
                    lastUpdated: needsTimestampUpdate ? now : (existing?.lastUpdated ?? now)
                )
            }
        }

        do {
            try configStore.save(config)
            oneRepMaxStatus = "1RM values saved."
            loadOneRepMaxFields()
        } catch {
            oneRepMaxStatus = "Failed to save 1RM values: \(error.localizedDescription)"
        }
    }

    func oneRepMaxDictionary() -> [String: Double] {
        let config = configStore.load()
        var result: [String: Double] = [:]
        for (lift, entry) in config.oneRepMaxes where entry.valueKG >= 20 {
            result[lift] = entry.valueKG
        }
        return result
    }

    // TEMP: TEST HARNESS — REMOVE AFTER VERIFICATION
    var testHarnessPayloadPreview: String {
        if testHarnessFortInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter Fort workout input above to preview the Claude API payload."
        }
        let oneRMs = oneRepMaxDictionary()
        let input = PlanGenerationInput(
            monday: testHarnessFortInput,
            wednesday: "WEDNESDAY\nRest day placeholder",
            friday: "FRIDAY\nRest day placeholder"
        )
        let oneRMSection: String
        if oneRMs.isEmpty {
            oneRMSection = "ATHLETE 1RM PROFILE:\nNo 1RM data provided."
        } else {
            let lines = oneRMs.sorted(by: { $0.key < $1.key }).map { exercise, value in
                String(format: "- %@: %.1f kg", exercise, value)
            }
            oneRMSection = "ATHLETE 1RM PROFILE:\n" + lines.joined(separator: "\n")
        }
        return """
        === PAYLOAD PREVIEW ===
        Model: claude-sonnet-4-6
        Max tokens: 2048
        System: "You generate deterministic weekly workout plans..."

        === 1RM SECTION ===
        \(oneRMSection)

        === FORT INPUT (Monday slot) ===
        \(input.monday)

        === FULL PROMPT LENGTH ===
        ~\(testHarnessFortInput.count + oneRMSection.count + 1200) chars (estimated)
        """
    }

    var testHarnessCanSend: Bool {
        !testHarnessFortInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !testHarnessIsSending
            && setupState.validate().isEmpty
    }

    func sendTestHarnessRequest() async {
        guard testHarnessCanSend else { return }
        testHarnessIsSending = true
        testHarnessResult = .empty
        defer { testHarnessIsSending = false }

        let oneRMs = oneRepMaxDictionary()

        do {
            testHarnessResult = try await gateway.sendTestHarnessRequest(
                fortInput: testHarnessFortInput,
                oneRepMaxes: oneRMs
            )
        } catch {
            testHarnessResult = APITestHarnessResult(
                prompt: "",
                rawResponse: "",
                model: "",
                inputTokens: 0,
                outputTokens: 0,
                responseTimeSeconds: 0,
                containsOneRepMax: false,
                oneRepMaxExercises: [],
                errorMessage: error.localizedDescription
            )
        }
    }

    func clearTestHarnessResult() {
        testHarnessResult = .empty
        testHarnessFortInput = ""
        testHarnessShowPayload = false
    }

    func applyTestHarnessTemplate() {
        testHarnessFortInput = """
        MONDAY
        IGNITION
        Deadbug 3x10
        Cat-Cow 2x8
        CLUSTER SET
        Back Squat 4x5 @ 80% 1RM
        AUXILIARY
        Reverse Pec Deck 3x15
        THAW
        BikeErg 10 min easy
        """
    }
    // END TEMP: TEST HARNESS

    func quickNavigate(to target: AppRoute) {
        route = target
    }

    func applyGenerationTemplate(day: String) {
        switch day.lowercased() {
        case "monday":
            generationInput.monday = """
            MONDAY
            IGNITION
            Deadbug
            CLUSTER SET
            Back Squat
            AUXILIARY
            Reverse Pec Deck
            THAW
            BikeErg
            """
        case "wednesday":
            generationInput.wednesday = """
            WEDNESDAY
            PREP
            Hip Airplane
            WORKING SET
            Bench Press
            AUXILIARY
            Rope Pressdown
            THAW
            Incline Walk
            """
        case "friday":
            generationInput.friday = """
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
        default:
            break
        }
    }

    func clearGenerationInput() {
        generationInput = PlanGenerationInput()
    }

    func normalizeGenerationInput() {
        generationInput = PlanGenerationInput(
            monday: normalizedMultiline(generationInput.monday),
            wednesday: normalizedMultiline(generationInput.wednesday),
            friday: normalizedMultiline(generationInput.friday)
        )
    }

    func resetPlanFilters() {
        planSearchQuery = ""
        showPlanNotes = true
        showPlanLogs = false
        showPlanLoggedOnly = false
        planBlockFilter = "All Blocks"
    }

    func copyStatusText() -> String {
        statusBanner.text
    }

    func copyGenerationInputsText() -> String {
        [
            "MONDAY INPUT",
            normalizedMultiline(generationInput.monday),
            "",
            "WEDNESDAY INPUT",
            normalizedMultiline(generationInput.wednesday),
            "",
            "FRIDAY INPUT",
            normalizedMultiline(generationInput.friday),
        ].joined(separator: "\n")
    }

    func buildSelectedPlanDayExportText() -> String {
        guard let day = selectedPlanDetail else {
            return ""
        }

        var lines: [String] = []
        lines.append("\(day.dayLabel) | \(planSnapshot.title)")
        lines.append("")

        for row in filteredPlanExercises {
            lines.append("\(row.block). \(row.exercise)")
            lines.append("- \(row.sets) x \(row.reps) @ \(row.load) kg")
            if !row.rest.isEmpty {
                lines.append("- Rest: \(row.rest)")
            }
            if !row.notes.isEmpty {
                lines.append("- Notes: \(row.notes)")
            }
            if showPlanLogs, !row.log.isEmpty {
                lines.append("- Log: \(row.log)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    func moveToAdjacentPlanDay(step: Int) {
        guard !orderedPlanDays.isEmpty,
              let index = orderedPlanDays.firstIndex(where: { $0.dayLabel == selectedPlanDay })
        else {
            return
        }

        let next = index + step
        guard next >= 0, next < orderedPlanDays.count else {
            return
        }
        selectedPlanDay = orderedPlanDays[next].dayLabel
    }

    func markDraftDone(draftID: UUID) {
        mutateDraft(draftID) { draft in
            draft.performance = "Done"
            if normalizedWhitespace(draft.rpe).isEmpty {
                draft.rpe = "8"
            }
        }
    }

    func markDraftSkip(draftID: UUID) {
        mutateDraft(draftID) { draft in
            draft.performance = "Skip"
        }
    }

    func clearDraftEntry(draftID: UUID) {
        mutateDraft(draftID) { draft in
            draft.performance = ""
            draft.rpe = ""
            draft.noteEntry = ""
        }
    }

    func markAllDraftsDone() {
        for index in loggerSession.drafts.indices {
            loggerSession.drafts[index].performance = "Done"
            if normalizedWhitespace(loggerSession.drafts[index].rpe).isEmpty {
                loggerSession.drafts[index].rpe = "8"
            }
        }
    }

    func clearAllDraftEntries() {
        for index in loggerSession.drafts.indices {
            loggerSession.drafts[index].performance = ""
            loggerSession.drafts[index].rpe = ""
            loggerSession.drafts[index].noteEntry = ""
        }
    }

    func resetLoggerFilters() {
        loggerSearchQuery = ""
        showLoggerIncompleteOnly = false
        loggerBlockFilter = "All Blocks"
    }

    func shouldShowDraft(_ draft: WorkoutLogDraft) -> Bool {
        let blockFilter = normalizedWhitespace(loggerBlockFilter)
        if !blockFilter.isEmpty,
           blockFilter != "All Blocks",
           normalizedWhitespace(draft.block).caseInsensitiveCompare(blockFilter) != .orderedSame {
            return false
        }

        let query = normalizedWhitespace(loggerSearchQuery).lowercased()
        if !query.isEmpty {
            let haystack = [
                draft.block,
                draft.exercise,
                draft.sets,
                draft.reps,
                draft.load,
                draft.rest,
                draft.notes,
                draft.existingLog,
                draft.performance,
                draft.rpe,
                draft.noteEntry,
            ].joined(separator: " ").lowercased()
            if !haystack.contains(query) {
                return false
            }
        }

        if !showLoggerIncompleteOnly {
            return true
        }
        return !isDraftComplete(draft)
    }

    func isValidRPE(_ raw: String) -> Bool {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) else {
            return false
        }
        return value >= 1 && value <= 10
    }

    func isDraftComplete(_ draft: WorkoutLogDraft) -> Bool {
        !normalizedWhitespace(draft.existingLog).isEmpty ||
            !normalizedWhitespace(draft.performance).isEmpty ||
            !normalizedWhitespace(draft.rpe).isEmpty ||
            !normalizedWhitespace(draft.noteEntry).isEmpty
    }

    func draftCompletionIcon(_ draft: WorkoutLogDraft) -> String {
        if isDraftComplete(draft) {
            return "checkmark.circle.fill"
        }
        return "circle"
    }

    func formatTimestamp(_ date: Date?) -> String {
        guard let date else {
            return "Not refreshed yet"
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeStyle = .short
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func mutateDraft(_ draftID: UUID, mutate: (inout WorkoutLogDraft) -> Void) {
        guard let index = loggerSession.drafts.firstIndex(where: { $0.id == draftID }) else {
            return
        }

        mutate(&loggerSession.drafts[index])
    }

    private func sanitizedLoggerSession(_ session: LoggerSessionState) -> LoggerSessionState {
        let drafts = session.drafts.map { draft in
            let normalizedRPE = normalizedWhitespace(draft.rpe).replacingOccurrences(of: ",", with: ".")
            return WorkoutLogDraft(
                id: draft.id,
                sourceRow: draft.sourceRow,
                block: normalizedWhitespace(draft.block),
                exercise: normalizedWhitespace(draft.exercise),
                sets: normalizedWhitespace(draft.sets),
                reps: normalizedWhitespace(draft.reps),
                load: normalizedWhitespace(draft.load),
                rest: normalizedWhitespace(draft.rest),
                notes: normalizedWhitespace(draft.notes),
                existingLog: normalizedWhitespace(draft.existingLog),
                performance: normalizedWhitespace(draft.performance),
                rpe: normalizedRPE,
                noteEntry: normalizedWhitespace(draft.noteEntry)
            )
        }

        return LoggerSessionState(
            sheetName: normalizedWhitespace(session.sheetName),
            dayLabel: normalizedWhitespace(session.dayLabel),
            source: session.source,
            drafts: drafts
        )
    }

    private func severity(for message: String) -> StatusSeverity {
        let lower = message.lowercased()
        if lower.contains("failed") || lower.contains("error") || lower.contains("unable") || lower.contains("incorrect") {
            return .error
        }
        if lower.contains("auth") || lower.contains("oauth") || lower.contains("token") || lower.contains("re-auth") {
            return .warning
        }
        if lower.contains("missing") || lower.contains("warn") || lower.contains("skipped") {
            return .warning
        }
        if lower.contains("saved") || lower.contains("complete") || lower.contains("updated") || lower.contains("success") {
            return .success
        }
        return .info
    }

    private func estimatedVolume(for row: PlanExerciseRow) -> Double {
        let sets = numericValue(from: row.sets)
        let reps = numericValue(from: row.reps)
        let load = numericValue(from: row.load)
        if sets <= 0 || reps <= 0 || load <= 0 {
            return 0
        }
        return sets * reps * load
    }

    private func numericValue(from raw: String) -> Double {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        if let exact = Double(normalized) {
            return exact
        }

        let pattern = #"\d+(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)),
              let range = Range(match.range(at: 0), in: normalized)
        else {
            return 0
        }

        return Double(normalized[range]) ?? 0
    }

    private func completionRate(of row: WeeklyReviewSummary) -> Double {
        if row.totalCount == 0 {
            return 0
        }
        return (Double(row.loggedCount) / Double(row.totalCount)) * 100
    }

    private func dayOrderIndex(dayLabel: String) -> Int {
        let upper = dayLabel.uppercased()
        let order = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]
        if let index = order.firstIndex(where: { upper.contains($0) }) {
            return index
        }
        return 99
    }

    private func normalizedWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedMultiline(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func nonEmptyLineCount(_ value: String) -> Int {
        value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private func stableDigest(_ value: String) -> String {
        var hash: UInt64 = 1469598103934665603
        let prime: UInt64 = 1099511628211
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(format: "%08llx", hash & 0xffffffff)
    }

    private func restoreFromConfig() {
        let config = configStore.load()
        if config == .empty {
            return
        }

        setupState = SetupState(
            anthropicAPIKey: config.anthropicAPIKey,
            spreadsheetID: config.spreadsheetID,
            googleAuthHint: config.googleAuthHint,
            localAppPassword: config.localAppPassword
        )
        isSetupComplete = true
        isUnlocked = config.localAppPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        loadOneRepMaxFields()
        Task {
            await refreshPlanSnapshot()
            await refreshLoggerSession()
        }
    }

    private func persistConfig() {
        let existingConfig = configStore.load()
        let config = NativeAppConfiguration(
            anthropicAPIKey: setupState.anthropicAPIKey,
            spreadsheetID: setupState.spreadsheetID,
            googleAuthHint: setupState.googleAuthHint,
            localAppPassword: setupState.localAppPassword,
            oneRepMaxes: existingConfig.oneRepMaxes
        )
        do {
            try configStore.save(config)
        } catch {
            generationStatus = "Failed to save app config: \(error.localizedDescription)"
        }
    }
}
