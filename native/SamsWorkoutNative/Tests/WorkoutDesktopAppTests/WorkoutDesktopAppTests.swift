import XCTest
@testable import WorkoutDesktopApp
import WorkoutIntegrations

@MainActor
final class WorkoutDesktopAppTests: XCTestCase {
    private final class TestConfigStore: AppConfigurationStore {
        private var config: NativeAppConfiguration = .empty

        func load() -> NativeAppConfiguration {
            config
        }

        func save(_ config: NativeAppConfiguration) throws {
            self.config = config
        }
    }

    private func makeCoordinator() -> AppCoordinator {
        AppCoordinator(gateway: InMemoryAppGateway(), configStore: TestConfigStore())
    }

    private func dateUTC(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date ?? Date()
    }

    func testRouteParityIncludesAllTargets() {
        let expected: Set<AppRoute> = [
            .dashboard,
            .generatePlan,
            .viewPlan,
            .logWorkout,
            .progress,
            .weeklyReview,
            .exerciseHistory,
            .dbStatus,
        ]
        XCTAssertEqual(Set(AppRoute.allCases), expected)
    }

    func testSetupValidationRequiresKeyAndSpreadsheetID() {
        let coordinator = makeCoordinator()
        coordinator.completeSetup()
        XCTAssertFalse(coordinator.isSetupComplete)
        XCTAssertEqual(coordinator.setupErrors.count, 2)

        coordinator.setupState.anthropicAPIKey = "key"
        coordinator.setupState.spreadsheetID = "1S9Bh_f69Hgy4iqgtqT9F-t1CR6eiN9e6xJecyHyDBYU"
        coordinator.completeSetup()
        XCTAssertTrue(coordinator.isSetupComplete)
        XCTAssertTrue(coordinator.setupErrors.isEmpty)
        XCTAssertTrue(coordinator.isUnlocked)
    }

    func testGenerationGuardPreventsRunWhenInputsMissing() async {
        let coordinator = makeCoordinator()
        await coordinator.runGeneration()
        XCTAssertTrue(coordinator.generationStatus.contains("Missing day input"))

        coordinator.generationInput.monday = "MONDAY\nIGNITION\nDeadbug"
        coordinator.generationInput.wednesday = "WEDNESDAY\nPREP\nHip Airplane"
        coordinator.generationInput.friday = "FRIDAY\nIGNITION\nMcGill Big-3"
        coordinator.setupState.anthropicAPIKey = "key"
        coordinator.setupState.spreadsheetID = "1S9Bh_f69Hgy4iqgtqT9F-t1CR6eiN9e6xJecyHyDBYU"
        coordinator.setupState.googleAuthHint = "/tmp/token.json"
        await coordinator.runGeneration()
        XCTAssertTrue(coordinator.generationStatus.contains("Plan generation wiring complete"))
    }

    func testRecoveryActionsUpdateStatus() async {
        let coordinator = makeCoordinator()
        coordinator.triggerReauth()
        XCTAssertTrue(coordinator.generationStatus.contains("Re-auth"))

        await coordinator.triggerRebuildDBCache()
        XCTAssertTrue(coordinator.generationStatus.contains("DB cache rebuild complete"))
        XCTAssertFalse(coordinator.dbRebuildSummary.isEmpty)
        XCTAssertNotNil(coordinator.lastDBRebuildAt)
    }

    func testUnlockFlowWithPassword() {
        let coordinator = makeCoordinator()
        coordinator.setupState.anthropicAPIKey = "key"
        coordinator.setupState.spreadsheetID = "1S9Bh_f69Hgy4iqgtqT9F-t1CR6eiN9e6xJecyHyDBYU"
        coordinator.setupState.localAppPassword = "1234"
        coordinator.completeSetup()

        XCTAssertTrue(coordinator.isSetupComplete)
        XCTAssertFalse(coordinator.isUnlocked)

        coordinator.unlockInput = "wrong"
        coordinator.unlock()
        XCTAssertFalse(coordinator.isUnlocked)
        XCTAssertTrue(coordinator.unlockError.contains("Incorrect"))

        coordinator.unlockInput = "1234"
        coordinator.unlock()
        XCTAssertTrue(coordinator.isUnlocked)
        XCTAssertTrue(coordinator.unlockError.isEmpty)
    }

    func testPreferredWeeklyPlanSheetPrefersNearCurrentWeekOverFarFuture() {
        let reference = dateUTC(2026, 2, 22)
        let sheetNames = [
            "Weekly Plan (2/16/2026)",
            "Weekly Plan (2/23/2026)",
            "Weekly Plan (1/5/2099)",
        ]

        let preferred = LiveAppGateway.testPreferredWeeklyPlanSheetName(sheetNames, referenceDate: reference)
        XCTAssertEqual(preferred, "Weekly Plan (2/23/2026)")
    }

    func testPreferredWeeklyPlanSheetFallsBackToMostRecentWhenOnlyFarFutureExists() {
        let reference = dateUTC(2026, 2, 22)
        let sheetNames = [
            "Weekly Plan (12/29/2098)",
            "Weekly Plan (1/5/2099)",
        ]

        let preferred = LiveAppGateway.testPreferredWeeklyPlanSheetName(sheetNames, referenceDate: reference)
        XCTAssertEqual(preferred, "Weekly Plan (1/5/2099)")
    }

    func testPreferredCandidateCanRejectFarFutureWithoutFallback() {
        let reference = dateUTC(2026, 2, 22)
        let farOnly: [(String, Date)] = [
            ("workout_plan_weekly_plan_1_5_2099.md", dateUTC(2099, 1, 5))
        ]

        let preferred = LiveAppGateway.testPreferredCandidate(
            farOnly,
            referenceDate: reference,
            nearWindowDays: 35,
            fallbackToMostRecent: false
        )

        XCTAssertNil(preferred)
    }

    func testParseLocalPlanDateFromFileName() {
        let parsed = LiveAppGateway.testParseLocalPlanDate(from: "workout_plan_weekly_plan_2_23_2026.md")
        XCTAssertEqual(parsed, dateUTC(2026, 2, 23))
        XCTAssertNil(LiveAppGateway.testParseLocalPlanDate(from: "workout_plan_manual.md"))
    }

    func testParseExistingLogSupportsNoteMarker() {
        let parsed = LiveAppGateway.testParseExistingLog("Done | RPE 8 | note: steady")
        XCTAssertEqual(parsed.0, "Done")
        XCTAssertEqual(parsed.1, "8")
        XCTAssertEqual(parsed.2, "steady")
    }

    func testLoggerWorkoutSelectionFallsBackToFirstNonEmptyDay() {
        let monday = SheetDayWorkout(dayLabel: "Monday", dayName: "Monday", exercises: [])
        let tuesday = SheetDayWorkout(
            dayLabel: "Tuesday",
            dayName: "Tuesday",
            exercises: [
                SheetDayExercise(
                    sourceRow: 12,
                    block: "A1",
                    exercise: "Back Squat",
                    sets: "5",
                    reps: "3",
                    load: "100",
                    rest: "180",
                    notes: "",
                    log: ""
                )
            ]
        )

        let selected = LiveAppGateway.testSelectLoggerWorkout([monday, tuesday], todayName: "Monday")
        XCTAssertEqual(selected?.dayName, "Tuesday")
        XCTAssertEqual(selected?.exercises.count, 1)
    }

    func testGenerationTemplateAndResetHelpers() {
        let coordinator = makeCoordinator()
        coordinator.applyGenerationTemplate(day: "monday")
        coordinator.applyGenerationTemplate(day: "wednesday")
        coordinator.applyGenerationTemplate(day: "friday")
        XCTAssertTrue(coordinator.generationInput.monday.contains("MONDAY"))
        XCTAssertTrue(coordinator.generationInput.wednesday.contains("WEDNESDAY"))
        XCTAssertTrue(coordinator.generationInput.friday.contains("FRIDAY"))

        coordinator.clearGenerationInput()
        XCTAssertTrue(coordinator.generationInput.monday.isEmpty)
        XCTAssertTrue(coordinator.generationInput.wednesday.isEmpty)
        XCTAssertTrue(coordinator.generationInput.friday.isEmpty)
    }

    func testPlanFilteringStatsAndExport() {
        let coordinator = makeCoordinator()
        coordinator.planSnapshot = PlanSnapshot(
            title: "Weekly Plan (2/23/2026)",
            source: .localCache,
            days: [
                PlanDayDetail(
                    id: "Monday",
                    dayLabel: "Monday",
                    source: .localCache,
                    exercises: [
                        PlanExerciseRow(sourceRow: 1, block: "A1", exercise: "Back Squat", sets: "5", reps: "3", load: "100", rest: "180", notes: "Depth", log: "Done"),
                        PlanExerciseRow(sourceRow: 2, block: "B1", exercise: "Reverse Pec Deck", sets: "3", reps: "15", load: "38", rest: "90", notes: "Scap", log: ""),
                    ]
                ),
            ],
            summary: "Loaded"
        )
        coordinator.selectedPlanDay = "Monday"
        coordinator.planSearchQuery = "squat"
        XCTAssertEqual(coordinator.filteredPlanExercises.count, 1)
        XCTAssertEqual(coordinator.planDayStats.exerciseCount, 1)
        XCTAssertGreaterThan(coordinator.planDayStats.estimatedVolumeKG, 0)

        coordinator.showPlanLogs = true
        let exported = coordinator.buildSelectedPlanDayExportText()
        XCTAssertTrue(exported.contains("Back Squat"))
        XCTAssertTrue(exported.contains("Weekly Plan (2/23/2026)"))
    }

    func testLoggerHelpersValidateRPEAndBulkActions() {
        let coordinator = makeCoordinator()
        coordinator.loggerSession = LoggerSessionState(
            sheetName: "Weekly Plan (2/23/2026)",
            dayLabel: "Tuesday",
            source: .googleSheets,
            drafts: [
                WorkoutLogDraft(
                    sourceRow: 3,
                    block: "A1",
                    exercise: "Back Squat",
                    sets: "5",
                    reps: "3",
                    load: "100",
                    rest: "180",
                    notes: "",
                    existingLog: ""
                ),
                WorkoutLogDraft(
                    sourceRow: 4,
                    block: "B1",
                    exercise: "Bench Press",
                    sets: "4",
                    reps: "6",
                    load: "80",
                    rest: "120",
                    notes: "",
                    existingLog: ""
                ),
            ]
        )

        coordinator.markDraftDone(draftID: coordinator.loggerSession.drafts[0].id)
        XCTAssertEqual(coordinator.loggerSession.drafts[0].performance, "Done")
        XCTAssertEqual(coordinator.loggerSession.drafts[0].rpe, "8")

        coordinator.loggerSession.drafts[1].rpe = "11"
        XCTAssertTrue(coordinator.hasInvalidLoggerEntries)
        XCTAssertFalse(coordinator.isValidRPE("11"))
        XCTAssertTrue(coordinator.isValidRPE("8,5"))

        coordinator.markAllDraftsDone()
        XCTAssertEqual(coordinator.loggerCompletionCount, 2)
        coordinator.clearAllDraftEntries()
        XCTAssertEqual(coordinator.loggerCompletionCount, 0)
    }

    func testWeeklyReviewFilterAndSortModes() {
        let coordinator = makeCoordinator()
        coordinator.weeklyReviewSummaries = [
            WeeklyReviewSummary(sheetName: "Weekly Plan (2/9/2026)", sessions: 6, loggedCount: 50, totalCount: 70, completionRateText: "71.4%"),
            WeeklyReviewSummary(sheetName: "Weekly Plan (2/23/2026)", sessions: 6, loggedCount: 63, totalCount: 63, completionRateText: "100.0%"),
            WeeklyReviewSummary(sheetName: "Weekly Plan (2/16/2026)", sessions: 5, loggedCount: 20, totalCount: 70, completionRateText: "28.6%"),
        ]

        coordinator.weeklyReviewQuery = "2/23"
        XCTAssertEqual(coordinator.filteredWeeklyReviewSummaries.count, 1)
        XCTAssertEqual(coordinator.filteredWeeklyReviewSummaries.first?.sheetName, "Weekly Plan (2/23/2026)")

        coordinator.weeklyReviewQuery = ""
        coordinator.weeklyReviewSort = .highestCompletion
        XCTAssertEqual(coordinator.filteredWeeklyReviewSummaries.first?.sheetName, "Weekly Plan (2/23/2026)")

        coordinator.weeklyReviewSort = .lowestCompletion
        XCTAssertEqual(coordinator.filteredWeeklyReviewSummaries.first?.sheetName, "Weekly Plan (2/16/2026)")
    }

    func testGenerationReadinessDetectsMissingHeaderAndDuplicates() {
        let coordinator = makeCoordinator()
        coordinator.setupState.anthropicAPIKey = "key"
        coordinator.setupState.spreadsheetID = "1S9Bh_f69Hgy4iqgtqT9F-t1CR6eiN9e6xJecyHyDBYU"
        coordinator.setupState.googleAuthHint = "/tmp/token.json"
        coordinator.generationInput.monday = "MONDAY\nBack Squat"
        coordinator.generationInput.wednesday = "bench press"
        coordinator.generationInput.friday = "bench press"

        let report = coordinator.generationReadinessReport
        XCTAssertFalse(report.isReady)
        XCTAssertTrue(report.missingHeaders.contains("Wednesday"))
        XCTAssertTrue(report.duplicatedDayPairs.contains(where: { $0.contains("Wednesday and Friday") }))
        XCTAssertFalse(coordinator.generationDisabledReason.isEmpty)
    }

    func testGenerationNormalizeInputPreservesLineBreaksAndTrimsNoise() {
        let coordinator = makeCoordinator()
        coordinator.generationInput.monday = " MONDAY \n\n  IGNITION   \n  Deadbug  \n"
        coordinator.normalizeGenerationInput()
        XCTAssertEqual(coordinator.generationInput.monday, "MONDAY\nIGNITION\nDeadbug")
    }

    func testPlanFiltersSupportBlockAndLoggedOnly() {
        let coordinator = makeCoordinator()
        coordinator.planSnapshot = PlanSnapshot(
            title: "Weekly Plan (2/23/2026)",
            source: .localCache,
            days: [
                PlanDayDetail(
                    id: "Monday",
                    dayLabel: "Monday",
                    source: .localCache,
                    exercises: [
                        PlanExerciseRow(sourceRow: 1, block: "A1", exercise: "Back Squat", sets: "5", reps: "3", load: "100", rest: "", notes: "", log: "Done"),
                        PlanExerciseRow(sourceRow: 2, block: "B1", exercise: "Reverse Pec Deck", sets: "3", reps: "15", load: "38", rest: "", notes: "", log: ""),
                    ]
                )
            ],
            summary: "Loaded"
        )
        coordinator.selectedPlanDay = "Monday"

        XCTAssertEqual(coordinator.planBlockCatalog, ["All Blocks", "A1", "B1"])
        coordinator.planBlockFilter = "A1"
        XCTAssertEqual(coordinator.filteredPlanExercises.count, 1)
        XCTAssertEqual(coordinator.planVisibleExerciseCount, 1)

        coordinator.planBlockFilter = "All Blocks"
        coordinator.showPlanLoggedOnly = true
        XCTAssertEqual(coordinator.filteredPlanExercises.count, 1)
        XCTAssertEqual(coordinator.planDayCompletionCount, 1)
        XCTAssertEqual(Int(coordinator.planDayCompletionPercent.rounded()), 100)
    }

    func testLoggerBlockFilterAndSaveDisabledReason() {
        let coordinator = makeCoordinator()
        coordinator.loggerSession = LoggerSessionState(
            sheetName: "Weekly Plan (2/23/2026)",
            dayLabel: "Tuesday",
            source: .googleSheets,
            drafts: [
                WorkoutLogDraft(
                    sourceRow: 3,
                    block: "A1",
                    exercise: "Back Squat",
                    sets: "5",
                    reps: "3",
                    load: "100",
                    rest: "180",
                    notes: "",
                    existingLog: ""
                ),
                WorkoutLogDraft(
                    sourceRow: 4,
                    block: "B1",
                    exercise: "Bench Press",
                    sets: "4",
                    reps: "6",
                    load: "80",
                    rest: "120",
                    notes: "",
                    existingLog: ""
                ),
            ]
        )

        coordinator.loggerBlockFilter = "B1"
        XCTAssertEqual(coordinator.loggerBlockCatalog, ["All Blocks", "A1", "B1"])
        XCTAssertFalse(coordinator.shouldShowDraft(coordinator.loggerSession.drafts[0]))
        XCTAssertTrue(coordinator.shouldShowDraft(coordinator.loggerSession.drafts[1]))

        coordinator.loggerSession.drafts[0].rpe = "15"
        XCTAssertTrue(coordinator.loggerSaveDisabledReason.contains("invalid RPE"))
    }

    func testWeeklyReviewSummaryHelpersExposeAverageBestWorst() {
        let coordinator = makeCoordinator()
        coordinator.weeklyReviewSummaries = [
            WeeklyReviewSummary(sheetName: "Weekly Plan (2/9/2026)", sessions: 6, loggedCount: 50, totalCount: 70, completionRateText: "71.4%"),
            WeeklyReviewSummary(sheetName: "Weekly Plan (2/23/2026)", sessions: 6, loggedCount: 63, totalCount: 63, completionRateText: "100.0%"),
            WeeklyReviewSummary(sheetName: "Weekly Plan (2/16/2026)", sessions: 5, loggedCount: 20, totalCount: 70, completionRateText: "28.6%"),
        ]

        XCTAssertEqual(coordinator.weeklyReviewBestWeek?.sheetName, "Weekly Plan (2/23/2026)")
        XCTAssertEqual(coordinator.weeklyReviewWorstWeek?.sheetName, "Weekly Plan (2/16/2026)")
        XCTAssertEqual(Int(coordinator.weeklyReviewAverageCompletion.rounded()), 67)
    }

    func testDBRebuildDisabledReasonRequiresSetup() {
        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator.dbRebuildDisabledReason.contains("spreadsheet ID"))

        coordinator.setupState.spreadsheetID = "1S9Bh_f69Hgy4iqgtqT9F-t1CR6eiN9e6xJecyHyDBYU"
        XCTAssertTrue(coordinator.dbRebuildDisabledReason.contains("Google auth token"))

        coordinator.setupState.googleAuthHint = "/tmp/token.json"
        XCTAssertTrue(coordinator.dbRebuildDisabledReason.isEmpty)
    }

    func testSanitizedSheetReferenceDatePreventsFarFutureYear() {
        let now = dateUTC(2026, 2, 22)
        let farFuture = dateUTC(2099, 1, 5)
        let result = LiveAppGateway.testSanitizedSheetReferenceDate(referenceDate: farFuture, nowDate: now)
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: result.0)

        XCTAssertTrue(result.1)
        XCTAssertEqual(year, 2026)
    }

    func testSetupChecklistAndCompletionPercent() {
        let coordinator = makeCoordinator()
        XCTAssertEqual(Int(coordinator.setupCompletionPercent.rounded()), 25)
        XCTAssertTrue(coordinator.setupMissingSummary.contains("Anthropic API key"))

        coordinator.setupState.anthropicAPIKey = "key"
        coordinator.setupState.spreadsheetID = "1S9Bh_f69Hgy4iqgtqT9F-t1CR6eiN9e6xJecyHyDBYU"
        coordinator.setupState.googleAuthHint = "/tmp/token.json"
        XCTAssertEqual(Int(coordinator.setupCompletionPercent.rounded()), 100)
    }

    func testGenerationFingerprintStableForSameNormalizedInputs() {
        let coordinator = makeCoordinator()
        coordinator.generationInput.monday = "MONDAY\nIGNITION\nDeadbug"
        coordinator.generationInput.wednesday = "WEDNESDAY\nPREP\nHip Airplane"
        coordinator.generationInput.friday = "FRIDAY\nIGNITION\nMcGill Big-3"
        let first = coordinator.generationInputFingerprint

        coordinator.generationInput.monday = " MONDAY \n IGNITION \n Deadbug "
        coordinator.generationInput.wednesday = "WEDNESDAY\nPREP\nHip Airplane"
        coordinator.generationInput.friday = "FRIDAY\nIGNITION\nMcGill Big-3"
        let second = coordinator.generationInputFingerprint

        XCTAssertEqual(first, second)
    }

    func testOrderedPlanDaysAndPositionText() {
        let coordinator = makeCoordinator()
        coordinator.planSnapshot = PlanSnapshot(
            title: "Weekly Plan (2/23/2026)",
            source: .localCache,
            days: [
                PlanDayDetail(id: "Friday", dayLabel: "Friday", source: .localCache, exercises: []),
                PlanDayDetail(id: "Monday", dayLabel: "Monday", source: .localCache, exercises: []),
                PlanDayDetail(id: "Wednesday", dayLabel: "Wednesday", source: .localCache, exercises: []),
            ],
            summary: ""
        )
        coordinator.selectedPlanDay = "Wednesday"
        XCTAssertEqual(coordinator.orderedPlanDays.map(\.dayLabel), ["Monday", "Wednesday", "Friday"])
        XCTAssertEqual(coordinator.selectedPlanDayPositionText, "Day 2 of 3")
    }

    func testLoggerSearchAndBlockProgressRows() {
        let coordinator = makeCoordinator()
        coordinator.loggerSession = LoggerSessionState(
            sheetName: "Weekly Plan (2/23/2026)",
            dayLabel: "Tuesday",
            source: .googleSheets,
            drafts: [
                WorkoutLogDraft(sourceRow: 3, block: "A1", exercise: "Back Squat", sets: "5", reps: "3", load: "100", rest: "180", notes: "", existingLog: "Done"),
                WorkoutLogDraft(sourceRow: 4, block: "B1", exercise: "Bench Press", sets: "4", reps: "6", load: "80", rest: "120", notes: "", existingLog: ""),
            ]
        )
        coordinator.loggerSearchQuery = "bench"
        XCTAssertEqual(coordinator.loggerVisibleCount, 1)
        XCTAssertEqual(coordinator.loggerPendingVisibleCount, 1)
        XCTAssertEqual(coordinator.loggerBlockProgressRows.count, 2)
        XCTAssertEqual(coordinator.loggerBlockProgressRows.first(where: { $0.block == "A1" })?.completed, 1)
    }

    func testHistoryEmptyReasonAndDBRebuildFormattingHelpers() {
        let coordinator = makeCoordinator()
        coordinator.selectedHistoryExercise = "Unknown Lift"
        coordinator.exerciseCatalog = []
        XCTAssertTrue(coordinator.historyEmptyReason.contains("No matching exercise"))

        coordinator.dbRebuildSummary = "Imported 10 rows. DB totals: 4 exercises."
        XCTAssertEqual(coordinator.formattedDBRebuildSummaryLines.count, 2)
        XCTAssertTrue(coordinator.formattedDBRebuildSummaryLines[0].hasSuffix("."))
    }
}
