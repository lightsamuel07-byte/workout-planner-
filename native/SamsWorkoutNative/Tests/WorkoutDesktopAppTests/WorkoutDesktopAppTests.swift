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
            .progress,
            .weeklyReview,
            .exerciseHistory,
            .settings,
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

    func testGenerationProgressStateUpdatesFromGatewayCallbacks() async {
        let coordinator = makeCoordinator()
        coordinator.generationInput.monday = "MONDAY\nIGNITION\nDeadbug"
        coordinator.generationInput.wednesday = "WEDNESDAY\nPREP\nHip Airplane"
        coordinator.generationInput.friday = "FRIDAY\nIGNITION\nMcGill Big-3"
        coordinator.setupState.anthropicAPIKey = "key"
        coordinator.setupState.spreadsheetID = "1S9Bh_f69Hgy4iqgtqT9F-t1CR6eiN9e6xJecyHyDBYU"
        coordinator.setupState.googleAuthHint = "/tmp/token.json"

        await coordinator.runGeneration()
        for _ in 0..<5 where coordinator.generationProgressLog.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(coordinator.generationStage, .completed)
        XCTAssertFalse(coordinator.generationProgressLog.isEmpty)
    }

    func testRebuildDBCacheUpdatesStatus() async {
        let coordinator = makeCoordinator()
        await coordinator.triggerRebuildDBCache()
        XCTAssertTrue(coordinator.generationStatus.contains("DB cache rebuild complete"))
        XCTAssertFalse(coordinator.dbRebuildSummary.isEmpty)
        XCTAssertNotNil(coordinator.lastDBRebuildAt)
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

    func testMarkdownDayParserHandlesFlexiblePrescriptionSyntax() {
        let plan = """
        ## MONDAY
        ### A1. Face Pull
        - 3 x 15 reps @ 18 kg
        - **Rest:** 1:00
        - **Notes:** Controlled.
        ### A2. Farmer Carry
        - 3 x 30 meters @ 32 kg (per hand)
        - **Rest:** 1:30
        - **Notes:** Brace.
        ### A3. McGill Big-3
        - 1 x See Notes @ Bodyweight
        - **Rest:** 0:45
        - **Notes:** Hold durations in notes.
        """

        let days = LiveAppGateway.testMarkdownDaysToPlanDays(plan)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].exercises.count, 3)
        XCTAssertEqual(days[0].exercises[0].sets, "3")
        XCTAssertEqual(days[0].exercises[0].reps, "15")
        XCTAssertEqual(days[0].exercises[0].load, "18")
        XCTAssertEqual(days[0].exercises[1].reps, "30")
        XCTAssertEqual(days[0].exercises[1].load, "32")
        XCTAssertEqual(days[0].exercises[2].reps, "See Notes")
        XCTAssertEqual(days[0].exercises[2].load, "Bodyweight")
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

    func testGenerationClearResetsAllInputs() {
        let coordinator = makeCoordinator()
        coordinator.generationInput.monday = "MONDAY\nSome Fort text"
        coordinator.generationInput.wednesday = "WEDNESDAY\nSome Fort text"
        coordinator.generationInput.friday = "FRIDAY\nSome Fort text"

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

    func testGenerationReadinessReportPassesWhenAllDaysHaveContent() {
        let coordinator = makeCoordinator()
        coordinator.generationInput.monday = "MONDAY\nIGNITION\nDeadbug\nBack Squat"
        coordinator.generationInput.wednesday = "WEDNESDAY\nPREP\nHip Airplane\nBench Press"
        coordinator.generationInput.friday = "FRIDAY\nIGNITION\nMcGill Big-3\nDeadlift"
        XCTAssertTrue(coordinator.generationReadinessReport.isReady)
        XCTAssertEqual(coordinator.generationIssueCount, 0)
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
        XCTAssertEqual(Int(coordinator.setupCompletionPercent.rounded()), 0)
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

    func testHistoryEmptyReasonAndDBRebuildFormattingHelpers() {
        let coordinator = makeCoordinator()
        coordinator.selectedHistoryExercise = "Unknown Lift"
        coordinator.exerciseCatalog = []
        XCTAssertTrue(coordinator.historyEmptyReason.contains("No matching exercise"))

        coordinator.dbRebuildSummary = "Imported 10 rows. DB totals: 4 exercises."
        XCTAssertEqual(coordinator.formattedDBRebuildSummaryLines.count, 2)
        XCTAssertTrue(coordinator.formattedDBRebuildSummaryLines[0].hasSuffix("."))
    }

    // MARK: - One Rep Max Tests

    func testOneRepMaxFieldValidation() {
        var field = OneRepMaxFieldState(id: "squat", liftName: "Back Squat", inputText: "", lastUpdated: nil)
        XCTAssertTrue(field.isValid, "Empty input should be valid (optional)")
        XCTAssertNil(field.parsedValue)
        XCTAssertEqual(field.lastUpdatedText, "Not set")

        field.inputText = "140"
        XCTAssertTrue(field.isValid)
        XCTAssertEqual(field.parsedValue, 140.0)
        XCTAssertTrue(field.validationMessage.isEmpty)

        field.inputText = "15"
        XCTAssertFalse(field.isValid)
        XCTAssertNil(field.parsedValue)
        XCTAssertTrue(field.validationMessage.contains("20"))

        field.inputText = "305"
        XCTAssertFalse(field.isValid)
        XCTAssertNil(field.parsedValue)
        XCTAssertTrue(field.validationMessage.contains("300"))

        field.inputText = "abc"
        XCTAssertFalse(field.isValid)
        XCTAssertNil(field.parsedValue)
        XCTAssertTrue(field.validationMessage.contains("numeric"))

        field.inputText = "142,5"
        XCTAssertTrue(field.isValid)
        XCTAssertEqual(field.parsedValue, 142.5)
    }

    func testOneRepMaxSaveAndRestore() {
        let coordinator = makeCoordinator()
        coordinator.loadOneRepMaxFields()
        XCTAssertEqual(coordinator.oneRepMaxFields.count, 3)
        XCTAssertFalse(coordinator.oneRepMaxesAreFilled)
        XCTAssertEqual(coordinator.oneRepMaxMissingLifts.count, 3)

        for index in coordinator.oneRepMaxFields.indices {
            coordinator.oneRepMaxFields[index].inputText = "\(100 + index * 20)"
        }
        coordinator.saveOneRepMaxes()
        XCTAssertTrue(coordinator.oneRepMaxStatus.contains("saved"))

        coordinator.loadOneRepMaxFields()
        XCTAssertTrue(coordinator.oneRepMaxesAreFilled)
        XCTAssertTrue(coordinator.oneRepMaxMissingLifts.isEmpty)

        let dict = coordinator.oneRepMaxDictionary()
        XCTAssertEqual(dict.count, 3)
        XCTAssertEqual(dict["Back Squat"], 100.0)
        XCTAssertEqual(dict["Bench Press"], 120.0)
        XCTAssertEqual(dict["Deadlift"], 140.0)
    }

    func testOneRepMaxGenerationWarning() {
        let coordinator = makeCoordinator()
        XCTAssertFalse(coordinator.oneRepMaxWarningForGeneration.isEmpty)
        XCTAssertTrue(coordinator.oneRepMaxWarningForGeneration.contains("Back Squat"))

        coordinator.loadOneRepMaxFields()
        for index in coordinator.oneRepMaxFields.indices {
            coordinator.oneRepMaxFields[index].inputText = "100"
        }
        coordinator.saveOneRepMaxes()
        XCTAssertTrue(coordinator.oneRepMaxWarningForGeneration.isEmpty)
    }

    func testOneRepMaxConfigPersistence() {
        let entry = OneRepMaxEntry(valueKG: 140.0, lastUpdated: Date())
        let config = NativeAppConfiguration(
            anthropicAPIKey: "key",
            spreadsheetID: "1S9Bh_f69Hgy4iqgtqT9F-t1CR6eiN9e6xJecyHyDBYU",
            googleAuthHint: "",
            oneRepMaxes: ["Back Squat": entry]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try! encoder.encode(config)
        let decoded = try! decoder.decode(NativeAppConfiguration.self, from: data)
        XCTAssertEqual(decoded.oneRepMaxes["Back Squat"]?.valueKG, 140.0)
        XCTAssertEqual(decoded.anthropicAPIKey, "key")
    }

    func testOneRepMaxMainLiftsConstant() {
        XCTAssertEqual(NativeAppConfiguration.mainLifts, ["Back Squat", "Bench Press", "Deadlift"])
    }

    // MARK: - Progress Page & New Analytics Tests

    func testWeeklyVolumePointsLoadFromInMemoryGateway() {
        let coordinator = makeCoordinator()
        coordinator.refreshAnalytics()
        XCTAssertEqual(coordinator.weeklyVolumePoints.count, 3)
        XCTAssertEqual(coordinator.weeklyVolumePoints.first?.sheetName, "Weekly Plan (2/9/2026)")
        XCTAssertGreaterThan(coordinator.weeklyVolumePoints.first?.volume ?? 0, 0)
    }

    func testWeeklyRPEPointsLoadFromInMemoryGateway() {
        let coordinator = makeCoordinator()
        coordinator.refreshAnalytics()
        XCTAssertEqual(coordinator.weeklyRPEPoints.count, 3)
        XCTAssertGreaterThan(coordinator.weeklyRPEPoints.first?.averageRPE ?? 0, 0)
        XCTAssertGreaterThan(coordinator.weeklyRPEPoints.first?.rpeCount ?? 0, 0)
    }

    func testMuscleGroupVolumesLoadFromInMemoryGateway() {
        let coordinator = makeCoordinator()
        coordinator.refreshAnalytics()
        XCTAssertEqual(coordinator.muscleGroupVolumes.count, 3)
        XCTAssertEqual(coordinator.muscleGroupVolumes.first?.muscleGroup, "CLUSTER SET")
        XCTAssertGreaterThan(coordinator.muscleGroupVolumes.first?.volume ?? 0, 0)
    }

    func testVolumeChartMaxReturnsHighestValue() {
        let coordinator = makeCoordinator()
        coordinator.weeklyVolumePoints = [
            WeeklyVolumePoint(sheetName: "W1", volume: 1000),
            WeeklyVolumePoint(sheetName: "W2", volume: 5000),
            WeeklyVolumePoint(sheetName: "W3", volume: 3000),
        ]
        XCTAssertEqual(coordinator.volumeChartMax, 5000)
    }

    func testVolumeChangeTextShowsPercentDelta() {
        let coordinator = makeCoordinator()
        coordinator.weeklyVolumePoints = [
            WeeklyVolumePoint(sheetName: "W2", volume: 11000),
            WeeklyVolumePoint(sheetName: "W1", volume: 10000),
        ]
        // Reversed: [W1: 10000, W2: 11000]. Latest = 11000, previous = 10000 => +10.0%
        XCTAssertEqual(coordinator.weeklyVolumeChangeText, "+10.0%")
    }

    func testAverageRPETextWeightedCorrectly() {
        let coordinator = makeCoordinator()
        coordinator.weeklyRPEPoints = [
            WeeklyRPEPoint(sheetName: "W1", averageRPE: 8.0, rpeCount: 10),
            WeeklyRPEPoint(sheetName: "W2", averageRPE: 7.0, rpeCount: 10),
        ]
        // Weighted: (8*10 + 7*10) / 20 = 7.5
        XCTAssertEqual(coordinator.averageRPEText, "7.5")
    }

    func testQuickNavigateChangesRoute() {
        let coordinator = makeCoordinator()
        XCTAssertEqual(coordinator.route, .dashboard)
        coordinator.quickNavigate(to: .progress)
        XCTAssertEqual(coordinator.route, .progress)
        coordinator.quickNavigate(to: .settings)
        XCTAssertEqual(coordinator.route, .settings)
    }

    func testMoveToAdjacentPlanDayNavigatesCorrectly() {
        let coordinator = makeCoordinator()
        coordinator.planSnapshot = PlanSnapshot(
            title: "Weekly Plan (2/23/2026)",
            source: .localCache,
            days: [
                PlanDayDetail(id: "Monday", dayLabel: "Monday", source: .localCache, exercises: []),
                PlanDayDetail(id: "Wednesday", dayLabel: "Wednesday", source: .localCache, exercises: []),
                PlanDayDetail(id: "Friday", dayLabel: "Friday", source: .localCache, exercises: []),
            ],
            summary: ""
        )
        coordinator.selectedPlanDay = "Monday"
        coordinator.moveToAdjacentPlanDay(step: 1)
        XCTAssertEqual(coordinator.selectedPlanDay, "Wednesday")
        coordinator.moveToAdjacentPlanDay(step: 1)
        XCTAssertEqual(coordinator.selectedPlanDay, "Friday")
        coordinator.moveToAdjacentPlanDay(step: 1)
        // Should not go past the end
        XCTAssertEqual(coordinator.selectedPlanDay, "Friday")
        coordinator.moveToAdjacentPlanDay(step: -1)
        XCTAssertEqual(coordinator.selectedPlanDay, "Wednesday")
    }

    // MARK: - UX Overhaul Tests

    func testShortDayNameExtractsAbbreviation() {
        let coordinator = makeCoordinator()
        XCTAssertEqual(coordinator.shortDayName(for: "MONDAY (FORT GAMEDAY #13)"), "Mon")
        XCTAssertEqual(coordinator.shortDayName(for: "TUESDAY (SUPPLEMENTAL - ARMS & CARRIES)"), "Tue")
        XCTAssertEqual(coordinator.shortDayName(for: "Wednesday"), "Wed")
        XCTAssertEqual(coordinator.shortDayName(for: "SATURDAY (SUPPLEMENTAL - BACK & HYPERTROPHY)"), "Sat")
        XCTAssertEqual(coordinator.shortDayName(for: "Unknown Label"), "Unknown La")
    }

    func testDaySubtitleExtractsParenthetical() {
        let coordinator = makeCoordinator()
        XCTAssertEqual(coordinator.daySubtitle(for: "MONDAY (FORT GAMEDAY #13)"), "FORT GAMEDAY #13")
        XCTAssertEqual(coordinator.daySubtitle(for: "TUESDAY (SUPPLEMENTAL - ARMS & CARRIES)"), "SUPPLEMENTAL - ARMS & CARRIES")
        XCTAssertEqual(coordinator.daySubtitle(for: "Wednesday"), "")
        XCTAssertEqual(coordinator.daySubtitle(for: "FRIDAY (FORT GAMEDAY #13)"), "FORT GAMEDAY #13")
    }

    func testSidebarVisibilityDefaultsToAll() {
        let coordinator = makeCoordinator()
        XCTAssertEqual(coordinator.sidebarVisibility, .all)
    }

    // MARK: - Sheets Write-back: parsePlanToSheetRows

    func testParsePlanToSheetRowsBasicDay() {
        // A minimal single-day markdown snippet with 2 exercises.
        // Verifies that Block, Exercise, Sets, Reps, Load, Rest, Notes are populated
        // correctly and that Log is always empty.
        let markdown = """
        ## TUESDAY
        ### B1. Incline DB Press (30°)
        - 4 x 10 @ 30 kg
        - **Rest:** 90 seconds
        - **Notes:** Control the eccentric. Elbows at 60°.
        ### B2. Cable Lateral Raise
        - 3 x 15 @ 8 kg
        - **Rest:** 60 seconds
        - **Notes:** Lead with elbow.
        """

        let rows = LiveAppGateway.testParsePlanToSheetRows(planText: markdown, dayLabel: "Tuesday")

        XCTAssertEqual(rows.count, 2, "Expected one row per exercise block")

        // First exercise
        let first = rows[0]
        XCTAssertEqual(first.count, 8, "Every row must have exactly 8 columns")
        XCTAssertEqual(first[0], "B1", "Column A: Block")
        XCTAssertEqual(first[1], "Incline DB Press (30°)", "Column B: Exercise")
        XCTAssertEqual(first[2], "4", "Column C: Sets")
        XCTAssertEqual(first[3], "10", "Column D: Reps")
        XCTAssertEqual(first[4], "30", "Column E: Load")
        XCTAssertEqual(first[5], "90 seconds", "Column F: Rest")
        XCTAssertEqual(first[6], "Control the eccentric. Elbows at 60°.", "Column G: Notes")
        XCTAssertEqual(first[7], "", "Column H: Log must be empty at generation time")

        // Second exercise
        let second = rows[1]
        XCTAssertEqual(second[0], "B2", "Column A: Block")
        XCTAssertEqual(second[1], "Cable Lateral Raise", "Column B: Exercise")
        XCTAssertEqual(second[2], "3", "Column C: Sets")
        XCTAssertEqual(second[3], "15", "Column D: Reps")
        XCTAssertEqual(second[4], "8", "Column E: Load")
        XCTAssertEqual(second[5], "60 seconds", "Column F: Rest")
        XCTAssertEqual(second[6], "Lead with elbow.", "Column G: Notes")
        XCTAssertEqual(second[7], "", "Column H: Log must be empty")
    }

    func testParsePlanToSheetRowsSkipsNonExerciseLines() {
        // Verifies that day headers, blank lines, and rest/notes lines do NOT produce
        // spurious rows — only exercise blocks (### Xn. Name) produce rows.
        let markdown = """
        ## THURSDAY

        This is a non-exercise preamble line.

        ### C1. DB Hammer Curl
        - 3 x 12 @ 16 kg
        - **Rest:** 60 seconds
        - **Notes:** Keep elbows pinned.

        Some stray text between exercises.

        ### C2. Rope Triceps Pressdown
        - 4 x 12 @ 20 kg
        - **Rest:** 45 seconds
        - **Notes:** Full extension at bottom.
        """

        let rows = LiveAppGateway.testParsePlanToSheetRows(planText: markdown, dayLabel: "Thursday")

        // Only the 2 exercise blocks should produce rows — headers, blanks, and prose lines must
        // be silently ignored.
        XCTAssertEqual(rows.count, 2, "Only exercise blocks produce rows; headers and prose must be skipped")
        XCTAssertEqual(rows[0][0], "C1")
        XCTAssertEqual(rows[0][1], "DB Hammer Curl")
        XCTAssertEqual(rows[1][0], "C2")
        XCTAssertEqual(rows[1][1], "Rope Triceps Pressdown")

        // Confirm no row represents the day header or stray text
        let allExerciseNames = rows.map { $0[1] }
        XCTAssertFalse(allExerciseNames.contains(where: { $0.contains("THURSDAY") || $0.contains("preamble") || $0.contains("stray") }),
                       "Day headers and prose must not appear as exercise names")
    }

    // MARK: - Two-Pass Generation Tests

    func testParseSelectedExercisesValidResponse() {
        let response = """
        Tuesday: DB Hammer Curl, Rope Pressdown, Face Pull, Incline Walk
        Thursday: 30 Degree Incline DB Press, Cable Lateral Raise, McGill Big-3, Incline Walk
        Saturday: EZ-Bar Curl, Overhead Triceps Extension, Rear Delt Fly, Incline Walk
        """

        let result = LiveAppGateway.testParseSelectedExercises(from: response)

        XCTAssertEqual(result.keys.sorted(), ["SATURDAY", "THURSDAY", "TUESDAY"])
        XCTAssertEqual(result["TUESDAY"]?.count, 4)
        XCTAssertEqual(result["THURSDAY"]?.count, 4)
        XCTAssertEqual(result["SATURDAY"]?.count, 4)
        XCTAssertTrue(result["TUESDAY"]?.contains("DB Hammer Curl") == true)
        XCTAssertTrue(result["THURSDAY"]?.contains("30 Degree Incline DB Press") == true)
        XCTAssertTrue(result["SATURDAY"]?.contains("EZ-Bar Curl") == true)
    }

    func testParseSelectedExercisesInvalidResponseFallsBackGracefully() {
        // Garbage inputs — should all return empty dict, not crash.
        let garbageInputs = [
            "",
            "No days here at all.",
            "Tuesday only, nothing else",
            "Tuesday: A, B\nThursday: C, D",  // Missing Saturday — incomplete
            "{ \"exercises\": [\"Back Squat\"] }",
        ]

        for input in garbageInputs {
            let result = LiveAppGateway.testParseSelectedExercises(from: input)
            XCTAssertTrue(
                result.isEmpty,
                "Expected empty dict for input '\(input.prefix(40))', got \(result)"
            )
        }
    }
}
