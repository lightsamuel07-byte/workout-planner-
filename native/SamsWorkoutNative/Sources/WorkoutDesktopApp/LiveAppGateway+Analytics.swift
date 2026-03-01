import Foundation
import WorkoutPersistence

extension LiveAppGateway {
    func loadExerciseHistory(exerciseName: String) -> [ExerciseHistoryPoint] {
        guard let database = try? openDatabase() else {
            return []
        }

        let points = (try? database.fetchExerciseHistory(exerciseName: exerciseName, limit: 24)) ?? []
        return points.map { point in
            ExerciseHistoryPoint(
                id: UUID(),
                dateISO: point.sessionDateISO,
                load: point.load,
                reps: point.reps,
                notes: point.notes
            )
        }
    }

    func loadExerciseCatalog(limit: Int = 200) -> [String] {
        guard let database = try? openDatabase() else {
            return []
        }
        return (try? database.fetchExerciseCatalog(limit: limit)) ?? []
    }

    func loadProgressSummary() -> ProgressSummary {
        guard let database = try? openDatabase(),
              let summary = try? database.fetchProgressSummary()
        else {
            return .empty
        }

        let completionRate: Double
        if summary.totalRows == 0 {
            completionRate = 0
        } else {
            completionRate = (Double(summary.loggedRows) / Double(summary.totalRows)) * 100
        }

        return ProgressSummary(
            completionRateText: String(format: "Completion rate: %.1f%%", completionRate),
            weeklyVolumeText: String(format: "Avg weekly volume (last 6): %.0f", summary.averageWeeklyVolume),
            recentLoggedText: "Recent logs (14d): \(summary.recentLoggedRows)",
            sourceText: "Source: Local DB cache"
        )
    }

    func loadWeeklyReviewSummaries() -> [WeeklyReviewSummary] {
        guard let database = try? openDatabase(),
              let summaries = try? database.fetchWeeklySummaries(limit: 12)
        else {
            return []
        }

        return summaries.map { row in
            let completion = row.totalCount == 0 ? 0 : (Double(row.loggedCount) / Double(row.totalCount)) * 100
            return WeeklyReviewSummary(
                sheetName: row.sheetName,
                sessions: row.sessions,
                loggedCount: row.loggedCount,
                totalCount: row.totalCount,
                completionRateText: String(format: "%.1f%%", completion)
            )
        }
    }

    func loadTopExercises(limit: Int = 5) -> [TopExerciseSummary] {
        guard let database = try? openDatabase(),
              let summaries = try? database.fetchTopExerciseSummaries(limit: limit)
        else {
            return []
        }

        return summaries.map { row in
            TopExerciseSummary(
                exerciseName: row.exerciseName,
                loggedCount: row.loggedCount,
                sessionCount: row.sessionCount
            )
        }
    }

    func loadRecentSessions(limit: Int = 8) -> [RecentSessionSummary] {
        let today = isoDate(nowProvider())
        guard let database = try? openDatabase(),
              let summaries = try? database.fetchRecentSessionSummaries(limit: limit, todayISO: today)
        else {
            return []
        }

        return summaries.map { row in
            RecentSessionSummary(
                sheetName: row.sheetName,
                dayLabel: row.dayLabel,
                sessionDateISO: row.sessionDateISO,
                loggedRows: row.loggedRows,
                totalRows: row.totalRows
            )
        }
    }

    func loadWeeklyVolumePoints(limit: Int = 12) -> [WeeklyVolumePoint] {
        guard let database = try? openDatabase(),
              let points = try? database.fetchWeeklyVolume(limit: limit)
        else {
            return []
        }

        return points.map { row in
            WeeklyVolumePoint(sheetName: row.sheetName, volume: row.volume)
        }
    }

    func loadWeeklyRPEPoints(limit: Int = 12) -> [WeeklyRPEPoint] {
        guard let database = try? openDatabase(),
              let points = try? database.fetchWeeklyRPE(limit: limit)
        else {
            return []
        }

        return points.map { row in
            WeeklyRPEPoint(sheetName: row.sheetName, averageRPE: row.averageRPE, rpeCount: row.rpeCount)
        }
    }

    func loadMuscleGroupVolumes(limit: Int = 12) -> [MuscleGroupVolume] {
        guard let database = try? openDatabase(),
              let volumes = try? database.fetchMuscleGroupVolume(limit: limit)
        else {
            return []
        }

        return volumes.map { row in
            MuscleGroupVolume(muscleGroup: row.muscleGroup, volume: row.volume, exerciseCount: row.exerciseCount)
        }
    }

    // MARK: - InBody Scans

    func loadInBodyScans() -> [InBodyScan] {
        guard let database = try? openDatabase(),
              let scans = try? database.fetchInBodyScans()
        else { return [] }

        return scans.map { s in
            InBodyScan(
                scanDate: s.scanDate,
                weightKG: s.weightKG,
                smmKG: s.smmKG,
                bfmKG: s.bfmKG,
                pbf: s.pbf,
                inbodyScore: s.inbodyScore,
                vfaCM2: s.vfaCM2,
                notes: s.notes
            )
        }
    }

    func saveInBodyScan(_ scan: InBodyScan) throws {
        let database = try openDatabase()
        let persisted = PersistedInBodyScan(
            id: 0,
            scanDate: scan.scanDate,
            weightKG: scan.weightKG,
            smmKG: scan.smmKG,
            bfmKG: scan.bfmKG,
            pbf: scan.pbf,
            inbodyScore: scan.inbodyScore,
            vfaCM2: scan.vfaCM2,
            notes: scan.notes
        )
        try database.upsertInBodyScan(persisted)
    }

    func deleteInBodyScan(scanDate: String) throws {
        let database = try openDatabase()
        try database.deleteInBodyScan(scanDate: scanDate)
    }
}
