import Foundation

public struct WeeklyPlanDescriptor: Equatable, Sendable {
    public let sheetName: String
    public let weekStartISO: String

    public init(sheetName: String, weekStartISO: String) {
        self.sheetName = sheetName
        self.weekStartISO = weekStartISO
    }
}

public struct WorkoutLogEntry: Equatable, Sendable {
    public let exerciseName: String
    public let logText: String

    public init(exerciseName: String, logText: String) {
        self.exerciseName = exerciseName
        self.logText = logText
    }
}

public enum NativeTrackFeature: String, CaseIterable, Sendable {
    case fortCompiler
    case planValidation
    case sheetsSync
    case analytics
}
