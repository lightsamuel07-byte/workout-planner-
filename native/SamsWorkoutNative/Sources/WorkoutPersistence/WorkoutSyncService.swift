import Foundation
import WorkoutCore

private let dayPattern = persistenceMakeRegex("\\b(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\\b", options: [.caseInsensitive])
private let inlineDatePattern = persistenceMakeRegex("(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?")
private let sheetDatePatterns: [NSRegularExpression] = [
    persistenceMakeRegex("Weekly Plan \\((\\d{1,2})/(\\d{1,2})/(\\d{4})\\)"),
    persistenceMakeRegex("\\(Weekly Plan\\)\\s*(\\d{1,2})/(\\d{1,2})/(\\d{4})"),
]
private let rpePattern = persistenceMakeRegex("\\brpe\\s*[:=]?\\s*(\\d+(?:\\.\\d+)?)\\b", options: [.caseInsensitive])

private let dayNameToIndex: [String: Int] = [
    "monday": 0,
    "tuesday": 1,
    "wednesday": 2,
    "thursday": 3,
    "friday": 4,
    "saturday": 5,
    "sunday": 6,
]

public struct WorkoutSyncService: Sendable {
    private let database: WorkoutDatabase

    public init(database: WorkoutDatabase) {
        self.database = database
    }

    public func sync(input: WorkoutSyncSessionInput) throws -> WorkoutDBSummary {
        let dayName = extractDayName(from: input.dayLabel) ?? input.fallbackDayName
        let sessionDate = inferSessionDate(
            sheetName: input.sheetName,
            dayLabel: input.dayLabel,
            dayName: dayName,
            fallbackDateISO: input.fallbackDateISO
        )

        let sessionID = try database.upsertSession(
            sheetName: input.sheetName,
            dayLabel: input.dayLabel,
            dayName: dayName,
            sessionDate: sessionDate
        )

        for entry in input.entries {
            let exerciseName = entry.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
            let logText = entry.logText.trimmingCharacters(in: .whitespacesAndNewlines)
            if exerciseName.isEmpty || (!input.includeEmptyLogs && logText.isEmpty) {
                continue
            }

            let exerciseID = try database.upsertExercise(exerciseName)
            let parsedRPE = coerceRPE(explicitRPE: entry.explicitRPE, logText: logText)
            try database.upsertExerciseLog(
                sessionID: sessionID,
                exerciseID: exerciseID,
                entry: entry,
                parsedRPE: parsedRPE
            )
        }

        return try database.countSummary()
    }

    public func extractDayName(from text: String) -> String? {
        if let match = dayPattern.firstMatch(in: text, options: [], range: persistenceFullRange(of: text)),
           let dayRange = Range(match.range(at: 1), in: text) {
            return String(text[dayRange]).capitalized
        }
        return nil
    }

    public func parseSheetAnchorDate(sheetName: String) -> Date? {
        for pattern in sheetDatePatterns {
            if let match = pattern.firstMatch(in: sheetName, options: [], range: persistenceFullRange(of: sheetName)),
               let monthRange = Range(match.range(at: 1), in: sheetName),
               let dayRange = Range(match.range(at: 2), in: sheetName),
               let yearRange = Range(match.range(at: 3), in: sheetName),
               let month = Int(sheetName[monthRange]),
               let day = Int(sheetName[dayRange]),
               let year = Int(sheetName[yearRange]) {
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = day
                components.calendar = Calendar(identifier: .gregorian)
                return components.date
            }
        }

        return nil
    }

    public func bestYearForMonthDay(anchorDate: Date?, month: Int, day: Int) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        guard let anchorDate else {
            return calendar.component(.year, from: Date())
        }

        let anchorYear = calendar.component(.year, from: anchorDate)
        var candidates: [Date] = []
        for year in [anchorYear - 1, anchorYear, anchorYear + 1] {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.calendar = calendar
            if let date = components.date {
                candidates.append(date)
            }
        }

        if candidates.isEmpty {
            return anchorYear
        }

        let nearest = candidates.min(by: {
            abs($0.timeIntervalSince(anchorDate)) < abs($1.timeIntervalSince(anchorDate))
        }) ?? anchorDate

        return calendar.component(.year, from: nearest)
    }

    public func inferDateFromAnchor(anchorDate: Date?, dayName: String?) -> Date? {
        guard let anchorDate, let dayName, let targetWeekday = dayNameToIndex[dayName.lowercased()] else {
            return nil
        }

        let calendar = Calendar(identifier: .gregorian)
        for offset in 0...6 {
            if let candidate = calendar.date(byAdding: .day, value: offset, to: anchorDate),
               calendar.component(.weekday, from: candidate) == targetWeekday + 2 {
                return candidate
            }
        }

        for offset in 1...7 {
            if let candidate = calendar.date(byAdding: .day, value: -offset, to: anchorDate),
               calendar.component(.weekday, from: candidate) == targetWeekday + 2 {
                return candidate
            }
        }

        return nil
    }

    public func inferSessionDate(sheetName: String, dayLabel: String, dayName: String?, fallbackDateISO: String) -> String {
        let anchorDate = parseSheetAnchorDate(sheetName: sheetName)

        if let inlineMatch = inlineDatePattern.firstMatch(in: dayLabel, options: [], range: persistenceFullRange(of: dayLabel)),
           let monthRange = Range(inlineMatch.range(at: 1), in: dayLabel),
           let dayRange = Range(inlineMatch.range(at: 2), in: dayLabel),
           let month = Int(dayLabel[monthRange]),
           let day = Int(dayLabel[dayRange]) {
            let year: Int
            if let yearRange = Range(inlineMatch.range(at: 3), in: dayLabel), !yearRange.isEmpty, let rawYear = Int(dayLabel[yearRange]) {
                year = rawYear < 100 ? rawYear + 2000 : rawYear
            } else {
                year = bestYearForMonthDay(anchorDate: anchorDate, month: month, day: day)
            }

            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.calendar = Calendar(identifier: .gregorian)
            if let date = components.date {
                return isoDate(date)
            }
        }

        if let inferred = inferDateFromAnchor(anchorDate: anchorDate, dayName: dayName) {
            return isoDate(inferred)
        }

        return fallbackDateISO
    }

    public func coerceRPE(explicitRPE: String, logText: String) -> Double? {
        let explicit = explicitRPE.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty, let value = Double(explicit), value >= 1.0, value <= 10.0 {
            return value
        }

        if let match = rpePattern.firstMatch(in: logText, options: [], range: persistenceFullRange(of: logText)),
           let range = Range(match.range(at: 1), in: logText),
           let value = Double(logText[range]),
           value >= 1.0,
           value <= 10.0 {
            return value
        }

        return nil
    }

    private func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
