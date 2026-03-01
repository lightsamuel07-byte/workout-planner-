import Foundation
import WorkoutIntegrations

enum PlanTextParser {
    private static let dayHeaderRegex = try! NSRegularExpression(pattern: "^##\\s+(.+)$", options: [])
    private static let exerciseHeaderRegex = try! NSRegularExpression(pattern: "^###\\s+([A-Z]\\d+)\\.\\s+(.+)$", options: [.caseInsensitive])
    private static let prescriptionRegex = try! NSRegularExpression(pattern: "^-\\s*(\\d+)\\s*x\\s*(.+?)\\s*@\\s*(.+)$", options: [.caseInsensitive])
    private static let prescriptionRepsUnitRegex = try! NSRegularExpression(
        pattern: "\\b(reps?|seconds?|secs?|minutes?|mins?|meters?|miles?)\\b",
        options: [.caseInsensitive]
    )
    private static let numericTokenRegex = try! NSRegularExpression(pattern: "[-+]?\\d+(?:\\.\\d+)?", options: [])

    static func markdownDaysToPlanDays(planText: String, source: DataSourceLabel) -> [PlanDayDetail] {
        let lines = planText.components(separatedBy: .newlines)
        var days: [PlanDayDetail] = []
        var currentDayLabel: String?
        var currentExercises: [PlanExerciseRow] = []
        var index = 0

        func flushDay() {
            guard let dayLabel = currentDayLabel else {
                return
            }
            days.append(
                PlanDayDetail(
                    id: dayLabel,
                    dayLabel: dayLabel,
                    source: source,
                    exercises: currentExercises
                )
            )
            currentDayLabel = nil
            currentExercises = []
        }

        while index < lines.count {
            let rawLine = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)

            if let match = firstMatch(dayHeaderRegex, text: rawLine),
               let dayLabel = match[0] {
                flushDay()
                currentDayLabel = dayLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                index += 1
                continue
            }

            if let match = firstMatch(exerciseHeaderRegex, text: rawLine),
               currentDayLabel != nil,
               let block = match[0],
               let exerciseName = match[1] {
                var sets = ""
                var reps = ""
                var load = ""
                var rest = ""
                var notes = ""

                var probeIndex = index + 1
                while probeIndex < lines.count {
                    let probe = lines[probeIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                    if firstMatch(exerciseHeaderRegex, text: probe) != nil || firstMatch(dayHeaderRegex, text: probe) != nil {
                        break
                    }

                    if let parsed = parsePrescriptionLine(probe) {
                        sets = parsed.sets
                        reps = parsed.reps
                        load = parsed.load
                    } else if probe.lowercased().hasPrefix("- **rest:**") {
                        rest = probe.replacingOccurrences(of: "- **Rest:**", with: "", options: [.caseInsensitive]).trimmingCharacters(in: .whitespaces)
                    } else if probe.lowercased().hasPrefix("- **notes:**") {
                        notes = probe.replacingOccurrences(of: "- **Notes:**", with: "", options: [.caseInsensitive]).trimmingCharacters(in: .whitespaces)
                    }
                    probeIndex += 1
                }

                currentExercises.append(
                    PlanExerciseRow(
                        sourceRow: nil,
                        block: block,
                        exercise: exerciseName,
                        sets: sets,
                        reps: reps,
                        load: load,
                        rest: rest,
                        notes: notes,
                        log: ""
                    )
                )

                index = probeIndex
                continue
            }

            index += 1
        }

        flushDay()
        return days
    }

    static func sheetDaysToPlanDays(values: [[String]], source: DataSourceLabel) -> [PlanDayDetail] {
        GoogleSheetsClient.parseDayWorkouts(values: values).map { workout in
            let rows = workout.exercises.map { exercise in
                PlanExerciseRow(
                    sourceRow: exercise.sourceRow,
                    block: exercise.block,
                    exercise: exercise.exercise,
                    sets: exercise.sets,
                    reps: exercise.reps,
                    load: exercise.load,
                    rest: exercise.rest,
                    notes: exercise.notes,
                    log: exercise.log
                )
            }
            return PlanDayDetail(
                id: workout.dayLabel,
                dayLabel: workout.dayLabel,
                source: source,
                exercises: rows
            )
        }
    }

    static func parsePlanToSheetRows(planText: String, dayLabel: String) -> [[String]] {
        // Parse line by line. Skip day headers, blank lines, and non-exercise lines.
        // Only `### Xn. Exercise Name` blocks produce rows.
        let lines = planText.components(separatedBy: .newlines)
        var rows: [[String]] = []

        var currentBlock = ""
        var currentExercise = ""
        var currentSets = ""
        var currentReps = ""
        var currentLoad = ""
        var currentRest = ""
        var currentNotes = ""
        var inExercise = false

        func flushExercise() {
            guard inExercise, !currentExercise.isEmpty else { return }
            rows.append(GoogleSheetsClient.enforceEightColumnSchema([
                currentBlock, currentExercise, currentSets, currentReps,
                currentLoad, currentRest, currentNotes,
                "",   // Log — always empty at generation time; user fills in after the workout
            ]))
            currentBlock = ""; currentExercise = ""; currentSets = ""; currentReps = ""
            currentLoad = ""; currentRest = ""; currentNotes = ""
            inExercise = false
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            // Day headers (## MONDAY, ## TUESDAY, etc.) — skip
            if line.hasPrefix("## ") {
                continue
            }

            // Exercise header: ### A1. Exercise Name
            if let match = firstMatch(exerciseHeaderRegex, text: line),
               let capturedBlock = match[0],
               let capturedExercise = match[1] {
                flushExercise()
                currentBlock = capturedBlock
                currentExercise = capturedExercise
                currentSets = ""; currentReps = ""; currentLoad = ""
                currentRest = ""; currentNotes = ""
                inExercise = true
                continue
            }

            guard inExercise else { continue }

            // Prescription line: - N x M @ Load kg
            if let parsed = parsePrescriptionLine(line) {
                currentSets = parsed.sets
                currentReps = parsed.reps
                currentLoad = parsed.load
                continue
            }

            // Rest line: - **Rest:** ...
            if line.lowercased().hasPrefix("- **rest:**") {
                currentRest = line
                    .replacingOccurrences(of: "- **Rest:**", with: "", options: [.caseInsensitive])
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            // Notes line: - **Notes:** ...
            if line.lowercased().hasPrefix("- **notes:**") {
                currentNotes = line
                    .replacingOccurrences(of: "- **Notes:**", with: "", options: [.caseInsensitive])
                    .trimmingCharacters(in: .whitespaces)
                continue
            }
        }

        flushExercise()
        return rows
    }

    static func makeSheetRows(planText: String, validationSummary: String, fidelitySummary: String) -> [[String]] {
        makeSheetRows(
            planText: planText,
            validationSummary: validationSummary,
            fidelitySummary: fidelitySummary,
            generatedAtISO: isoDateTime(Date())
        )
    }

    static func makeSheetRows(
        planText: String,
        validationSummary: String,
        fidelitySummary: String,
        generatedAtISO: String
    ) -> [[String]] {
        let days = markdownDaysToPlanDays(planText: planText, source: .localCache)
        var rows: [[String]] = []
        rows.append(["Workout Plan - Generated \(generatedAtISO)"])
        rows.append([])

        for day in days {
            rows.append([day.dayLabel])
            rows.append([])
            rows.append(["Block", "Exercise", "Sets", "Reps", "Load (kg)", "Rest", "Notes", "Log"])

            for exercise in day.exercises {
                rows.append([
                    exercise.block,
                    exercise.exercise,
                    exercise.sets,
                    exercise.reps,
                    exercise.load,
                    exercise.rest,
                    exercise.notes,
                    "",
                ])
            }
            rows.append([])
        }

        // Validation metadata is intentionally NOT written to the sheet —
        // it pollutes the sync data and creates noise rows in the exercise history.

        return rows.map { GoogleSheetsClient.enforceEightColumnSchema($0) }
    }

    static func parsePrescriptionLine(_ line: String) -> (sets: String, reps: String, load: String)? {
        guard let match = prescriptionRegex.firstMatch(in: line, options: [], range: nsRange(line)),
              let setsRange = Range(match.range(at: 1), in: line),
              let repsRange = Range(match.range(at: 2), in: line),
              let loadRange = Range(match.range(at: 3), in: line)
        else {
            return nil
        }

        let sets = String(line[setsRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let repsRaw = String(line[repsRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let loadRaw = String(line[loadRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        let repsSansUnits = prescriptionRepsUnitRegex.stringByReplacingMatches(
            in: repsRaw,
            options: [],
            range: nsRange(repsRaw),
            withTemplate: ""
        )
        let cleanedReps = repsSansUnits
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reps = cleanedReps.isEmpty ? repsRaw : cleanedReps

        let load: String
        if let loadMatch = numericTokenRegex.firstMatch(in: loadRaw, options: [], range: nsRange(loadRaw)),
           let tokenRange = Range(loadMatch.range(at: 0), in: loadRaw) {
            load = String(loadRaw[tokenRange])
        } else {
            load = loadRaw
        }

        return (sets, reps, load)
    }

    static func parseExistingLog(_ value: String) -> (performance: String, rpe: String, notes: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ("", "", "")
        }

        var performance = ""
        var rpe = ""
        var notes = ""

        let parts = trimmed.split(separator: "|").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for part in parts {
            let lower = part.lowercased()
            if lower.hasPrefix("rpe ") {
                rpe = part.replacingOccurrences(of: "RPE", with: "", options: [.caseInsensitive]).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("notes:") {
                notes = part.replacingOccurrences(of: "Notes:", with: "", options: [.caseInsensitive]).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("note:") {
                notes = part.replacingOccurrences(of: "Note:", with: "", options: [.caseInsensitive]).trimmingCharacters(in: .whitespaces)
            } else if performance.isEmpty {
                performance = part
            }
        }

        return (performance, rpe, notes)
    }

    static func selectLoggerWorkout(workouts: [SheetDayWorkout], todayName: String) -> SheetDayWorkout? {
        if let todayNonEmpty = workouts.first(where: {
            $0.dayName.caseInsensitiveCompare(todayName) == .orderedSame && !$0.exercises.isEmpty
        }) {
            return todayNonEmpty
        }

        if let firstNonEmpty = workouts.first(where: { !$0.exercises.isEmpty }) {
            return firstNonEmpty
        }

        return workouts.first(where: { $0.dayName.caseInsensitiveCompare(todayName) == .orderedSame }) ?? workouts.first
    }

    static func normalizedPlanTitle(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedPlanSummary(_ raw: String) -> String {
        normalizedPlanTitle(raw)
    }

    private static func isoDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func firstMatch(_ regex: NSRegularExpression, text: String) -> [String?]? {
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)) else {
            return nil
        }

        var captures: [String?] = []
        for idx in 1..<match.numberOfRanges {
            let range = match.range(at: idx)
            if range.location == NSNotFound {
                captures.append(nil)
            } else if let swiftRange = Range(range, in: text) {
                captures.append(String(text[swiftRange]))
            } else {
                captures.append(nil)
            }
        }
        return captures
    }

    private static func nsRange(_ value: String) -> NSRange {
        NSRange(value.startIndex..<value.endIndex, in: value)
    }
}
