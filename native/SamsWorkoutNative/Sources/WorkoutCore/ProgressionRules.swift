import Foundation

public struct PriorSupplementalExercise: Equatable, Sendable {
    public let exercise: String
    public let reps: String
    public let load: String
    public let log: String

    public init(exercise: String, reps: String, load: String, log: String) {
        self.exercise = exercise
        self.reps = reps
        self.load = load
        self.log = log
    }
}

public struct ProgressionRuleDirective: Equatable, Sendable {
    public let dayName: String
    public let exerciseName: String
    public let normalizedExercise: String
    public let signal: String
    public let reason: String
    public let holdLock: Bool
    public let targetReps: Int?
    public let targetLoad: Double?
    public let parsedRPE: Double?
    public let sourceLog: String

    public init(
        dayName: String,
        exerciseName: String,
        normalizedExercise: String,
        signal: String,
        reason: String,
        holdLock: Bool,
        targetReps: Int?,
        targetLoad: Double?,
        parsedRPE: Double?,
        sourceLog: String
    ) {
        self.dayName = dayName
        self.exerciseName = exerciseName
        self.normalizedExercise = normalizedExercise
        self.signal = signal
        self.reason = reason
        self.holdLock = holdLock
        self.targetReps = targetReps
        self.targetLoad = targetLoad
        self.parsedRPE = parsedRPE
        self.sourceLog = sourceLog
    }

    public func asPlanDirective() -> ProgressionDirective {
        ProgressionDirective(
            dayName: dayName,
            exerciseName: exerciseName,
            holdLock: holdLock,
            targetReps: targetReps.map(String.init),
            targetLoad: targetLoad
        )
    }
}

private let rpeValueRegex = makeRegex("\\brpe\\s*[:=]?\\s*(\\d+(?:\\.\\d+)?)\\b", options: [.caseInsensitive])

private let holdLockPatterns: [NSRegularExpression] = [
    "\\bkeep\\b",
    "\\bstay here\\b",
    "\\bhold\\b",
    "\\bsame weight\\b",
    "\\bdon't increase\\b",
    "\\bdo not increase\\b",
    "\\bcan't increase\\b",
].map { makeRegex($0, options: [.caseInsensitive]) }

private let strugglePatterns: [NSRegularExpression] = [
    "\\bhard\\b",
    "\\bheavy\\b",
    "\\btough\\b",
    "\\bstruggl",
    "\\bchalleng",
    "\\bfailed\\b",
    "\\bform (?:broke|breakdown|wasn't perfect)\\b",
].map { makeRegex($0, options: [.caseInsensitive]) }

private let exceededPatterns: [NSRegularExpression] = [
    "\\beasy\\b",
    "\\btoo light\\b",
    "\\bcould do more\\b",
    "\\breps? left\\b",
    "\\bgo up\\b",
    "\\bincrease\\b",
].map { makeRegex($0, options: [.caseInsensitive]) }

private let progressionDayOrder = ["Tuesday", "Thursday", "Saturday"]

private func parseFloat(_ value: String) -> Double? {
    Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func parseInt(_ value: String) -> Int? {
    Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func parseRPE(_ text: String) -> Double? {
    guard
        let match = rpeValueRegex.firstMatch(in: text, options: [], range: fullRange(of: text)),
        let range = Range(match.range(at: 1), in: text),
        let value = Double(text[range]),
        value >= 1.0,
        value <= 10.0
    else {
        return nil
    }

    return value
}

private func matchesAny(_ patterns: [NSRegularExpression], text: String) -> Bool {
    patterns.contains { $0.firstMatch(in: text, options: [], range: fullRange(of: text)) != nil }
}

private func classifySignal(logText: String, rpe: Double?) -> (String, String) {
    if matchesAny(holdLockPatterns, text: logText) {
        return ("hold_lock", "explicit_keep_instruction")
    }

    if matchesAny(strugglePatterns, text: logText) {
        return ("hold_lock", "struggle_signal")
    }

    if let rpe, rpe >= 9.0 {
        return ("hold_lock", "high_rpe")
    }

    if matchesAny(exceededPatterns, text: logText) {
        return ("progress", "exceeded_signal")
    }

    if let rpe, rpe <= 7.0 {
        return ("progress", "low_rpe")
    }

    return ("neutral", "no_strong_signal")
}

private func normalizeDayName(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

public func buildProgressionDirectives(priorSupplemental: [String: [PriorSupplementalExercise]]) -> [ProgressionRuleDirective] {
    if priorSupplemental.isEmpty {
        return []
    }

    var directives: [ProgressionRuleDirective] = []

    for dayName in progressionDayOrder {
        for exercise in priorSupplemental[dayName] ?? [] {
            let exerciseName = exercise.exercise.trimmingCharacters(in: .whitespacesAndNewlines)
            if exerciseName.isEmpty {
                continue
            }

            let logText = exercise.log.trimmingCharacters(in: .whitespacesAndNewlines)
            if logText.isEmpty {
                continue
            }

            let parsedRPE = parseRPE(logText)
            let (signal, reason) = classifySignal(logText: logText, rpe: parsedRPE)
            let targetReps = parseInt(exercise.reps)
            let targetLoad = parseFloat(exercise.load)

            directives.append(
                ProgressionRuleDirective(
                    dayName: normalizeDayName(dayName),
                    exerciseName: exerciseName,
                    normalizedExercise: getNormalizer().canonicalKey(exerciseName),
                    signal: signal,
                    reason: reason,
                    holdLock: signal == "hold_lock",
                    targetReps: targetReps,
                    targetLoad: targetLoad,
                    parsedRPE: parsedRPE,
                    sourceLog: logText
                )
            )
        }
    }

    return directives
}

private func formatLoad(_ value: Double?) -> String {
    guard let value else {
        return ""
    }
    if abs(value - round(value)) < 1e-9 {
        return String(Int(round(value)))
    }
    return String(format: "%.3f", value)
        .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
}

public func formatDirectivesForPrompt(_ directives: [ProgressionRuleDirective], maxLines: Int = 18) -> String {
    if directives.isEmpty {
        return ""
    }

    var lines = ["PROGRESSION DIRECTIVES (DETERMINISTIC FROM PRIOR LOGS):"]
    var holdLines: [String] = []
    var progressLines: [String] = []

    for directive in directives {
        let day = directive.dayName.capitalized
        let logPreview = String(directive.sourceLog.prefix(90))
        if directive.holdLock {
            let reps = directive.targetReps.map(String.init) ?? ""
            let load = formatLoad(directive.targetLoad)
            holdLines.append("- LOCK \(day) | \(directive.exerciseName) -> keep \(reps) reps @ \(load) kg | log: \(logPreview)")
        } else if directive.signal == "progress" {
            progressLines.append("- PROGRESS \(day) | \(directive.exerciseName) -> progression allowed (single-variable change) | log: \(logPreview)")
        }
    }

    lines.append(contentsOf: (holdLines + progressLines).prefix(maxLines))
    return lines.joined(separator: "\n")
}

private func findBestDirective(dayName: String?, exerciseName: String, directives: [ProgressionDirective]) -> ProgressionDirective? {
    guard let dayName else {
        return nil
    }

    let normalizer = getNormalizer()
    let targetDay = normalizeDayName(dayName)

    if let exact = directives.first(where: {
        normalizeDayName($0.dayName ?? "") == targetDay &&
            normalizer.canonicalKey($0.exerciseName) == normalizer.canonicalKey(exerciseName)
    }) {
        return exact
    }

    for directive in directives where normalizeDayName(directive.dayName ?? "") == targetDay {
        if normalizer.areSameExercise(exerciseName, directive.exerciseName) {
            return directive
        }
    }

    return nil
}

public func applyLockedDirectivesToPlan(planText: String, directives: [ProgressionDirective]) -> (String, Int) {
    if planText.isEmpty || directives.isEmpty {
        return (planText, 0)
    }

    let locked = directives.filter { $0.holdLock }
    if locked.isEmpty {
        return (planText, 0)
    }

    let dayRegex = makeRegex("^\\s*##\\s+([A-Z]+DAY)\\b", options: [.caseInsensitive])
    let exerciseRegex = makeRegex("^\\s*###\\s+[A-Z]\\d+\\.\\s*(.+)$", options: [.caseInsensitive])
    let prescriptionRegex = makeRegex("^(\\s*-\\s*)(\\d+)\\s*x\\s*([\\d:]+)\\s*@\\s*([\\d]+(?:\\.\\d+)?)\\s*kg(\\b.*)$", options: [.caseInsensitive])

    var currentDay: String?
    var currentExercise: String?
    var currentDirective: ProgressionDirective?
    var applied = 0
    var lines = planText.components(separatedBy: .newlines)

    for index in lines.indices {
        let line = lines[index]

        if let dayMatch = dayRegex.firstMatch(in: line, options: [], range: fullRange(of: line)),
           let dayRange = Range(dayMatch.range(at: 1), in: line) {
            currentDay = String(line[dayRange]).capitalized
            currentExercise = nil
            currentDirective = nil
            continue
        }

        if let exerciseMatch = exerciseRegex.firstMatch(in: line, options: [], range: fullRange(of: line)),
           let exerciseRange = Range(exerciseMatch.range(at: 1), in: line) {
            currentExercise = String(line[exerciseRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            currentDirective = findBestDirective(dayName: currentDay, exerciseName: currentExercise ?? "", directives: locked)
            continue
        }

        guard let directive = currentDirective else {
            continue
        }

        guard let prescriptionMatch = prescriptionRegex.firstMatch(in: line, options: [], range: fullRange(of: line)),
              let prefixRange = Range(prescriptionMatch.range(at: 1), in: line),
              let setsRange = Range(prescriptionMatch.range(at: 2), in: line),
              let suffixRange = Range(prescriptionMatch.range(at: 5), in: line),
              let targetReps = directive.targetReps,
              let targetLoad = directive.targetLoad
        else {
            continue
        }

        let prefix = String(line[prefixRange])
        let sets = String(line[setsRange])
        let suffix = String(line[suffixRange])
        let newLine = "\(prefix)\(sets) x \(targetReps) @ \(formatLoad(targetLoad)) kg\(suffix)"

        if newLine != line {
            lines[index] = newLine
            applied += 1
        }

        currentDirective = nil
    }

    return (lines.joined(separator: "\n"), applied)
}
