import XCTest
@testable import WorkoutDesktopApp

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
        coordinator.setupState.spreadsheetID = "sheet"
        coordinator.completeSetup()
        XCTAssertTrue(coordinator.isSetupComplete)
        XCTAssertTrue(coordinator.setupErrors.isEmpty)
        XCTAssertTrue(coordinator.isUnlocked)
    }

    func testGenerationGuardPreventsRunWhenInputsMissing() async {
        let coordinator = makeCoordinator()
        await coordinator.runGeneration()
        XCTAssertTrue(coordinator.generationStatus.contains("Missing Fort inputs"))

        coordinator.generationInput.monday = "monday"
        coordinator.generationInput.wednesday = "wednesday"
        coordinator.generationInput.friday = "friday"
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
    }

    func testUnlockFlowWithPassword() {
        let coordinator = makeCoordinator()
        coordinator.setupState.anthropicAPIKey = "key"
        coordinator.setupState.spreadsheetID = "sheet"
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
}
