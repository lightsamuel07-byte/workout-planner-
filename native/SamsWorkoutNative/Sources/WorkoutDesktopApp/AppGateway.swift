import Foundation
import WorkoutCore
import WorkoutIntegrations
import WorkoutPersistence

@MainActor
protocol NativeAppGateway {
    func initialRoute() -> AppRoute
    func loadDashboardDays() -> [DayPlanSummary]
    func generatePlan(input: PlanGenerationInput) async throws -> String
    func loadExerciseHistory(exerciseName: String) -> [ExerciseHistoryPoint]
    func loadExerciseCatalog(limit: Int) -> [String]
    func dbStatusText() -> String
    func rebuildDatabaseCache() async throws -> DBRebuildReport
    func loadPlanSnapshot(forceRemote: Bool) async throws -> PlanSnapshot
    func loadTodayLoggerSession() async throws -> LoggerSessionState
    func saveLoggerSession(_ session: LoggerSessionState) async throws -> WorkoutDBSummary
    func loadProgressSummary() -> ProgressSummary
    func loadWeeklyReviewSummaries() -> [WeeklyReviewSummary]
    func loadTopExercises(limit: Int) -> [TopExerciseSummary]
    func loadRecentSessions(limit: Int) -> [RecentSessionSummary]
    func loadDBHealthSnapshot() -> DBHealthSnapshot
    func loadWeeklyVolumePoints(limit: Int) -> [WeeklyVolumePoint]
    func loadWeeklyRPEPoints(limit: Int) -> [WeeklyRPEPoint]
    func loadMuscleGroupVolumes(limit: Int) -> [MuscleGroupVolume]
    // TEMP: TEST HARNESS — REMOVE AFTER VERIFICATION
    func sendTestHarnessRequest(fortInput: String, oneRepMaxes: [String: Double]) async throws -> APITestHarnessResult
    // END TEMP: TEST HARNESS
}

extension NativeAppGateway {
    func loadPlanSnapshot(forceRemote: Bool = false) async throws -> PlanSnapshot {
        let _ = forceRemote
        return PlanSnapshot.empty
    }

    func loadTodayLoggerSession() async throws -> LoggerSessionState {
        .empty
    }

    func loadExerciseCatalog(limit: Int = 200) -> [String] {
        let _ = limit
        return []
    }

    func rebuildDatabaseCache() async throws -> DBRebuildReport {
        DBRebuildReport(
            weeklySheetsScanned: 0,
            daySessionsImported: 0,
            exerciseRowsImported: 0,
            loggedRowsImported: 0,
            dbExercises: 0,
            dbSessions: 0,
            dbExerciseLogs: 0
        )
    }

    func saveLoggerSession(_ session: LoggerSessionState) async throws -> WorkoutDBSummary {
        let _ = session
        return WorkoutDBSummary(exercises: 0, sessions: 0, exerciseLogs: 0, logsWithRPE: 0)
    }

    func loadProgressSummary() -> ProgressSummary {
        .empty
    }

    func loadWeeklyReviewSummaries() -> [WeeklyReviewSummary] {
        []
    }

    func loadTopExercises(limit: Int = 5) -> [TopExerciseSummary] {
        let _ = limit
        return []
    }

    func loadRecentSessions(limit: Int = 8) -> [RecentSessionSummary] {
        let _ = limit
        return []
    }

    func loadDBHealthSnapshot() -> DBHealthSnapshot {
        .empty
    }

    func loadWeeklyVolumePoints(limit: Int = 12) -> [WeeklyVolumePoint] {
        let _ = limit
        return []
    }

    func loadWeeklyRPEPoints(limit: Int = 12) -> [WeeklyRPEPoint] {
        let _ = limit
        return []
    }

    func loadMuscleGroupVolumes(limit: Int = 12) -> [MuscleGroupVolume] {
        let _ = limit
        return []
    }

    // TEMP: TEST HARNESS — REMOVE AFTER VERIFICATION
    func sendTestHarnessRequest(fortInput: String, oneRepMaxes: [String: Double]) async throws -> APITestHarnessResult {
        let _ = fortInput
        let _ = oneRepMaxes
        return .empty
    }
    // END TEMP: TEST HARNESS
}

struct InMemoryAppGateway: NativeAppGateway {
    private let integrations = IntegrationsFacade()

    func initialRoute() -> AppRoute {
        .dashboard
    }

    func loadDashboardDays() -> [DayPlanSummary] {
        [
            DayPlanSummary(id: "monday", title: "MONDAY", source: .googleSheets, blocks: 6),
            DayPlanSummary(id: "tuesday", title: "TUESDAY", source: .googleSheets, blocks: 4),
            DayPlanSummary(id: "wednesday", title: "WEDNESDAY", source: .googleSheets, blocks: 6),
            DayPlanSummary(id: "thursday", title: "THURSDAY", source: .googleSheets, blocks: 4),
            DayPlanSummary(id: "friday", title: "FRIDAY", source: .googleSheets, blocks: 6),
            DayPlanSummary(id: "saturday", title: "SATURDAY", source: .googleSheets, blocks: 4),
        ]
    }

    func generatePlan(input: PlanGenerationInput) async throws -> String {
        let _ = input
        return "Plan generation wiring complete. Anthropic + validator flow will execute through integrations in runtime setup."
    }

    func loadExerciseHistory(exerciseName: String) -> [ExerciseHistoryPoint] {
        let normalizer = getNormalizer()
        let normalized = normalizer.canonicalName(exerciseName)
        let knownCanonicalNames: Set<String> = Set(
            loadExerciseCatalog(limit: 200).map { normalizer.canonicalName($0) }
        )
        if !knownCanonicalNames.contains(normalized) {
            return []
        }
        return [
            ExerciseHistoryPoint(id: UUID(), dateISO: "2026-02-10", load: 24.0, reps: "12", notes: "\(normalized) steady"),
            ExerciseHistoryPoint(id: UUID(), dateISO: "2026-02-17", load: 26.0, reps: "12", notes: "Progression"),
        ]
    }

    func loadExerciseCatalog(limit: Int = 200) -> [String] {
        let _ = limit
        return [
            "Back Squat",
            "Bench Press",
            "Reverse Pec Deck",
            "DB Hammer Curl",
            "Standing Calf Raise",
        ]
    }

    func dbStatusText() -> String {
        integrations.describeCurrentMode()
    }

    func rebuildDatabaseCache() async throws -> DBRebuildReport {
        DBRebuildReport(
            weeklySheetsScanned: 12,
            daySessionsImported: 72,
            exerciseRowsImported: 684,
            loggedRowsImported: 241,
            dbExercises: 98,
            dbSessions: 72,
            dbExerciseLogs: 684
        )
    }

    func loadPlanSnapshot(forceRemote: Bool = false) async throws -> PlanSnapshot {
        let _ = forceRemote
        return PlanSnapshot(
            title: "In-memory plan",
            source: .localCache,
            days: [],
            summary: "No live plan data in in-memory mode."
        )
    }

    func loadTodayLoggerSession() async throws -> LoggerSessionState {
        LoggerSessionState(
            sheetName: "Weekly Plan (2/23/2026)",
            dayLabel: "Tuesday",
            source: .googleSheets,
            drafts: []
        )
    }

    func loadTopExercises(limit: Int = 5) -> [TopExerciseSummary] {
        let _ = limit
        return [
            TopExerciseSummary(exerciseName: "Back Squat", loggedCount: 14, sessionCount: 8),
            TopExerciseSummary(exerciseName: "Bench Press", loggedCount: 12, sessionCount: 7),
            TopExerciseSummary(exerciseName: "Reverse Pec Deck", loggedCount: 10, sessionCount: 6),
        ]
    }

    func loadRecentSessions(limit: Int = 8) -> [RecentSessionSummary] {
        let _ = limit
        return [
            RecentSessionSummary(sheetName: "Weekly Plan (2/23/2026)", dayLabel: "Monday", sessionDateISO: "2026-02-23", loggedRows: 6, totalRows: 8),
            RecentSessionSummary(sheetName: "Weekly Plan (2/23/2026)", dayLabel: "Tuesday", sessionDateISO: "2026-02-24", loggedRows: 7, totalRows: 8),
        ]
    }

    func loadDBHealthSnapshot() -> DBHealthSnapshot {
        DBHealthSnapshot(
            exerciseCount: 98,
            sessionCount: 72,
            logCount: 684,
            nonEmptyLogCount: 241,
            latestSessionDateISO: "2026-02-24",
            topExercises: loadTopExercises(limit: 5),
            recentSessions: loadRecentSessions(limit: 8),
            weekdayCompletion: [
                WeekdayCompletionSummary(dayName: "Monday", loggedRows: 62, totalRows: 80),
                WeekdayCompletionSummary(dayName: "Tuesday", loggedRows: 44, totalRows: 60),
                WeekdayCompletionSummary(dayName: "Wednesday", loggedRows: 58, totalRows: 76),
            ]
        )
    }

    func loadWeeklyVolumePoints(limit: Int = 12) -> [WeeklyVolumePoint] {
        let _ = limit
        return [
            WeeklyVolumePoint(sheetName: "Weekly Plan (2/9/2026)", volume: 28500),
            WeeklyVolumePoint(sheetName: "Weekly Plan (2/16/2026)", volume: 31200),
            WeeklyVolumePoint(sheetName: "Weekly Plan (2/23/2026)", volume: 29800),
        ]
    }

    func loadWeeklyRPEPoints(limit: Int = 12) -> [WeeklyRPEPoint] {
        let _ = limit
        return [
            WeeklyRPEPoint(sheetName: "Weekly Plan (2/9/2026)", averageRPE: 7.2, rpeCount: 18),
            WeeklyRPEPoint(sheetName: "Weekly Plan (2/16/2026)", averageRPE: 7.8, rpeCount: 22),
            WeeklyRPEPoint(sheetName: "Weekly Plan (2/23/2026)", averageRPE: 7.5, rpeCount: 20),
        ]
    }

    func loadMuscleGroupVolumes(limit: Int = 12) -> [MuscleGroupVolume] {
        let _ = limit
        return [
            MuscleGroupVolume(muscleGroup: "CLUSTER SET", volume: 15000, exerciseCount: 3),
            MuscleGroupVolume(muscleGroup: "AUXILIARY", volume: 8500, exerciseCount: 6),
            MuscleGroupVolume(muscleGroup: "BREAKPOINT", volume: 6200, exerciseCount: 2),
        ]
    }
}
