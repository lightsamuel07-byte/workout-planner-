import XCTest
@testable import WorkoutCore

final class WorkoutCoreTests: XCTestCase {
    func testNativeTrackFeatureCount() {
        XCTAssertEqual(NativeTrackFeature.allCases.count, 4)
    }

    func testWeeklyPlanDescriptorInit() {
        let descriptor = WeeklyPlanDescriptor(
            sheetName: "Weekly Plan (2/23/2026)",
            weekStartISO: "2026-02-23"
        )
        XCTAssertEqual(descriptor.sheetName, "Weekly Plan (2/23/2026)")
        XCTAssertEqual(descriptor.weekStartISO, "2026-02-23")
    }
}
