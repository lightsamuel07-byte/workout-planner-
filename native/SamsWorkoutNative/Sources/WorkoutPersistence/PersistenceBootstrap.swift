import Foundation
import GRDB
import WorkoutCore

public struct PersistenceBootstrap {
    public init() {}

    public func openDatabase(at path: String) throws -> DatabaseQueue {
        let workoutDB = try WorkoutDatabase(path: path)
        try workoutDB.migrate()
        return workoutDB.dbQueue
    }

    public func makeWorkoutDatabase(at path: String) throws -> WorkoutDatabase {
        let workoutDB = try WorkoutDatabase(path: path)
        try workoutDB.migrate()
        return workoutDB
    }
}
