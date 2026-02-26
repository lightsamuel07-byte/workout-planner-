import Foundation
import Combine
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var route: AppRoute
    @Published var sidebarVisibility: NavigationSplitViewVisibility = .all
    @Published var setupState = SetupState()
    @Published var isSetupComplete = false
    @Published var setupErrors: [String] = []
    @Published var generationInput = PlanGenerationInput()
    @Published var generationStatus = ""
    @Published var isGenerating = false
    @Published var planSnapshot = PlanSnapshot.empty
    @Published var selectedPlanDay = ""
    @Published var viewPlanError = ""
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
    @Published var weeklyReviewQuery = ""
    @Published var weeklyReviewSort: WeeklyReviewSortMode = .newest

    @Published var lastPlanRefreshAt: Date?
    @Published var lastAnalyticsRefreshAt: Date?
    @Published var lastDBRebuildAt: Date?

    @Published var topExercises: [TopExerciseSummary] = []
    @Published var recentSessions: [RecentSessionSummary] = []
    @Published var weeklyVolumePoints: [WeeklyVolumePoint] = []
    @Published var weeklyRPEPoints: [WeeklyRPEPoint] = []
    @Published var muscleGroupVolumes: [MuscleGroupVolume] = []

    @Published var oneRepMaxFields: [OneRepMaxFieldState] = []
    @Published var oneRepMaxStatus = ""


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
        // Prefer live planSnapshot (Sheets data) when available; fallback to local cache.
        if !planSnapshot.days.isEmpty {
            return planSnapshot.days.map { day in
                DayPlanSummary(
                    id: day.dayLabel.lowercased(),
                    title: day.dayLabel.uppercased(),
                    source: day.source,
                    blocks: day.exercises.count
                )
            }
        }
        return gateway.loadDashboardDays()
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

if !generationStatus.isEmpty {
            return StatusBanner(text: generationStatus, severity: severity(for: generationStatus))
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

        return [
            SetupChecklistItem(id: "anthropic_key", title: "Anthropic API key provided", isComplete: keyReady),
            SetupChecklistItem(id: "sheet_id", title: "Spreadsheet ID provided", isComplete: sheetReady),
            SetupChecklistItem(id: "google_auth", title: "Google auth hint provided", isComplete: authReady),
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

    var volumeChartMax: Double {
        weeklyVolumePoints.map(\.volume).max() ?? 1
    }

    var rpeChartMax: Double {
        10.0
    }

    var muscleGroupVolumeMax: Double {
        muscleGroupVolumes.map(\.volume).max() ?? 1
    }

    var weeklyVolumeChangeText: String {
        let reversed = weeklyVolumePoints.reversed().map(\.volume)
        guard reversed.count >= 2 else { return "n/a" }
        let latest = reversed.last ?? 0
        let previous = reversed[reversed.count - 2]
        if previous == 0 { return "n/a" }
        let change = ((latest - previous) / previous) * 100
        let sign = change >= 0 ? "+" : ""
        return String(format: "%@%.1f%%", sign, change)
    }

    var averageRPEText: String {
        guard !weeklyRPEPoints.isEmpty else { return "n/a" }
        let totalWeighted = weeklyRPEPoints.reduce(0.0) { $0 + $1.averageRPE * Double($1.rpeCount) }
        let totalCount = weeklyRPEPoints.reduce(0) { $0 + $1.rpeCount }
        if totalCount == 0 { return "n/a" }
        return String(format: "%.1f", totalWeighted / Double(totalCount))
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
            googleAuthHint: normalizedWhitespace(setupState.googleAuthHint)
        )

        let errors = setupState.validate()
        setupErrors = errors
        if errors.isEmpty {
            isSetupComplete = true
            persistConfig()
            generationStatus = "Setup saved. Ready to use live workflows."
            Task {
                await refreshPlanSnapshot()
                await triggerRebuildDBCache()
            }
            refreshAnalytics()
        }
    }

    func markSetupIncomplete() {
        isSetupComplete = false
        planSnapshot = .empty
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

    func refreshPlanSnapshot(forceRemote: Bool = false) async {
        do {
            let snapshot = try await gateway.loadPlanSnapshot(forceRemote: forceRemote)
            planSnapshot = snapshot
            viewPlanError = ""
            lastPlanRefreshAt = Date()
            if selectedPlanDay.isEmpty || !orderedPlanDays.contains(where: { $0.dayLabel == selectedPlanDay }) {
                selectedPlanDay = orderedPlanDays.first?.dayLabel ?? ""
            }
            if !planBlockCatalog.contains(planBlockFilter) {
                planBlockFilter = "All Blocks"
            }
        } catch is CancellationError {
            // User navigated away before the fetch completed — not an error.
            return
        } catch {
            viewPlanError = "Unable to load plan: \(error.localizedDescription)"
            if planSnapshot.days.isEmpty {
                planSnapshot = .empty
            }
        }
    }

    func refreshAnalytics() {
        progressSummary = gateway.loadProgressSummary()
        weeklyReviewSummaries = gateway.loadWeeklyReviewSummaries()
        topExercises = gateway.loadTopExercises(limit: 5)
        recentSessions = gateway.loadRecentSessions(limit: 8)
        weeklyVolumePoints = gateway.loadWeeklyVolumePoints(limit: 12)
        weeklyRPEPoints = gateway.loadWeeklyRPEPoints(limit: 12)
        muscleGroupVolumes = gateway.loadMuscleGroupVolumes(limit: 12)
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

    func quickNavigate(to target: AppRoute) {
        route = target
    }

    func toggleSidebar() {
        withAnimation {
            sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly
        }
        NSApp.keyWindow?.firstResponder?.tryToPerform(
            #selector(NSSplitViewController.toggleSidebar(_:)), with: nil
        )
    }

    func shortDayName(for dayLabel: String) -> String {
        let upper = dayLabel.uppercased()
        let days = [
            ("MONDAY", "Mon"), ("TUESDAY", "Tue"), ("WEDNESDAY", "Wed"),
            ("THURSDAY", "Thu"), ("FRIDAY", "Fri"), ("SATURDAY", "Sat"), ("SUNDAY", "Sun"),
        ]
        for (full, short) in days where upper.contains(full) {
            return short
        }
        return String(dayLabel.prefix(10))
    }

    func daySubtitle(for dayLabel: String) -> String {
        if let openParen = dayLabel.firstIndex(of: "("),
           let closeParen = dayLabel.lastIndex(of: ")") {
            let inner = dayLabel[dayLabel.index(after: openParen)..<closeParen]
            return String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let upper = dayLabel.uppercased()
        if upper.contains("FORT") { return "Fort" }
        if upper.contains("SUPPLEMENTAL") { return "Supplemental" }
        return ""
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
            googleAuthHint: config.googleAuthHint
        )
        isSetupComplete = true
        loadOneRepMaxFields()
        Task {
            await refreshPlanSnapshot()
            // Rebuild DB cache in the background so log data is always fresh on launch.
            await triggerRebuildDBCache()
        }
    }

    private func persistConfig() {
        let existingConfig = configStore.load()
        let config = NativeAppConfiguration(
            anthropicAPIKey: setupState.anthropicAPIKey,
            spreadsheetID: setupState.spreadsheetID,
            googleAuthHint: setupState.googleAuthHint,
            oneRepMaxes: existingConfig.oneRepMaxes
        )
        do {
            try configStore.save(config)
        } catch {
            generationStatus = "Failed to save app config: \(error.localizedDescription)"
        }
    }
}
