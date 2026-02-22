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

    private let gateway: NativeAppGateway
    private let configStore: AppConfigurationStore

    init(gateway: NativeAppGateway = InMemoryAppGateway(), configStore: AppConfigurationStore = FileAppConfigurationStore()) {
        self.gateway = gateway
        self.configStore = configStore
        self.route = gateway.initialRoute()
        restoreFromConfig()
        refreshAnalytics()
        refreshExerciseCatalog()
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

    var selectedPlanDetail: PlanDayDetail? {
        if !selectedPlanDay.isEmpty,
           let match = planSnapshot.days.first(where: { $0.dayLabel == selectedPlanDay }) {
            return match
        }
        return planSnapshot.days.first
    }

    func completeSetup() {
        let errors = setupState.validate()
        setupErrors = errors
        if errors.isEmpty {
            isSetupComplete = true
            unlockError = ""
            isUnlocked = setupState.localAppPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            persistConfig()
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
        guard generationInput.canGenerate else {
            generationStatus = "Missing Fort inputs for Monday/Wednesday/Friday."
            return
        }

        isGenerating = true
        defer { isGenerating = false }

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
            if selectedPlanDay.isEmpty || !snapshot.days.contains(where: { $0.dayLabel == selectedPlanDay }) {
                selectedPlanDay = snapshot.days.first?.dayLabel ?? ""
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
        } catch {
            loggerStatus = "Unable to load workout logger: \(error.localizedDescription)"
            if loggerSession.drafts.isEmpty {
                loggerSession = .empty
            }
        }
    }

    func saveLoggerSession() async {
        do {
            let summary = try await gateway.saveLoggerSession(loggerSession)
            loggerStatus = "Saved logs. DB now has \(summary.exerciseLogs) log rows across \(summary.sessions) sessions."
            refreshAnalytics()
        } catch {
            loggerStatus = "Failed to save logs: \(error.localizedDescription)"
        }
    }

    func refreshAnalytics() {
        progressSummary = gateway.loadProgressSummary()
        weeklyReviewSummaries = gateway.loadWeeklyReviewSummaries()
        refreshExerciseCatalog()
    }

    func refreshExerciseCatalog() {
        exerciseCatalog = gateway.loadExerciseCatalog(limit: 240)
    }

    func applyHistorySuggestion(_ exerciseName: String) {
        selectedHistoryExercise = exerciseName
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
        Task {
            await refreshPlanSnapshot()
            await refreshLoggerSession()
        }
    }

    private func persistConfig() {
        let config = NativeAppConfiguration(
            anthropicAPIKey: setupState.anthropicAPIKey,
            spreadsheetID: setupState.spreadsheetID,
            googleAuthHint: setupState.googleAuthHint,
            localAppPassword: setupState.localAppPassword
        )
        do {
            try configStore.save(config)
        } catch {
            generationStatus = "Failed to save app config: \(error.localizedDescription)"
        }
    }
}
