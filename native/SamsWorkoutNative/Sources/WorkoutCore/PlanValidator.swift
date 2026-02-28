import Foundation

public struct PlanEntry: Equatable, Sendable {
    public let day: String?
    public let exercise: String
    public let normalizedExercise: String
    public let prescriptionLine: String
    public let sets: Int?
    public let reps: String?
    public let load: Double?
    public let rest: String
    public let notes: String

    public init(
        day: String?,
        exercise: String,
        normalizedExercise: String,
        prescriptionLine: String,
        sets: Int?,
        reps: String?,
        load: Double?,
        rest: String,
        notes: String
    ) {
        self.day = day
        self.exercise = exercise
        self.normalizedExercise = normalizedExercise
        self.prescriptionLine = prescriptionLine
        self.sets = sets
        self.reps = reps
        self.load = load
        self.rest = rest
        self.notes = notes
    }
}

/// Common interface for plan and fidelity violations, enabling typed collections
/// instead of `[Any]` type erasure in the correction loop.
public protocol ViolationDescribing: Sendable {
    var code: String { get }
    var message: String { get }
    var day: String { get }
    var exercise: String { get }
}

public struct PlanViolation: Equatable, Sendable, ViolationDescribing {
    public let code: String
    public let message: String
    public let day: String
    public let exercise: String

    public init(code: String, message: String, day: String = "", exercise: String = "") {
        self.code = code
        self.message = message
        self.day = day
        self.exercise = exercise
    }
}

public struct PlanValidationResult: Equatable, Sendable {
    public let entries: [PlanEntry]
    public let violations: [PlanViolation]
    public let summary: String

    public init(entries: [PlanEntry], violations: [PlanViolation], summary: String) {
        self.entries = entries
        self.violations = violations
        self.summary = summary
    }
}

public struct ProgressionDirective: Equatable, Sendable {
    public let dayName: String?
    public let exerciseName: String
    public let holdLock: Bool
    public let targetReps: String?
    public let targetLoad: Double?

    public init(
        dayName: String?,
        exerciseName: String,
        holdLock: Bool,
        targetReps: String?,
        targetLoad: Double?
    ) {
        self.dayName = dayName
        self.exerciseName = exerciseName
        self.holdLock = holdLock
        self.targetReps = targetReps
        self.targetLoad = targetLoad
    }
}

private let dayRegex = makeRegex("^\\s*##\\s+([A-Z]+DAY)\\b", options: [.caseInsensitive])
private let exerciseRegex = makeRegex("^\\s*###\\s+[A-Z]\\d+\\.\\s*(.+)$", options: [.caseInsensitive])
private let prescriptionRegex = makeRegex("^\\s*-\\s*(\\d+)\\s*x\\s*([\\d:]+)\\s*@\\s*([\\d]+(?:\\.\\d+)?)\\s*kg\\b", options: [.caseInsensitive])
private let rangeRegex = makeRegex("(\\d+)\\s*[-–]\\s*(\\d+)")
private let fortPseudoExercisePatterns: [NSRegularExpression] = [
    makeRegex("^PREPARE\\s+TO\\s+ENGAGE\\b", options: [.caseInsensitive]),
    makeRegex("^PULL[\\s\\-]*UPS?\\s+EVERY\\s+DAY\\b", options: [.caseInsensitive]),
    makeRegex("^THE\\s+REPLACEMENTS\\b", options: [.caseInsensitive]),
    makeRegex("^THE\\s+SWEAT\\s+BANK\\b", options: [.caseInsensitive]),
    makeRegex("^THE\\s+PAY\\s+OFF\\b", options: [.caseInsensitive]),
    makeRegex("^THAW\\b", options: [.caseInsensitive]),
    makeRegex("^ENGINE\\s+BUILDER\\b", options: [.caseInsensitive]),
    makeRegex("^SPARK\\s+ZONE\\b", options: [.caseInsensitive]),
    makeRegex("^VERTICAL\\s+LADDER\\b", options: [.caseInsensitive]),
    makeRegex("^PRIMARY\\s+DRIVER\\b", options: [.caseInsensitive]),
    makeRegex("^SUPPORT\\s+BUILDER\\b", options: [.caseInsensitive]),
    makeRegex("^EXAMPLES?\\b", options: [.caseInsensitive]),
    makeRegex("^METERS\\b", options: [.caseInsensitive]),
    makeRegex("^DIST\\.?\\s*\\((M|MI|MILES)\\)\\b", options: [.caseInsensitive]),
    makeRegex("^\\d+\\s*SECONDS?\\s+AT\\s+\\d+(?:\\.\\d+)?\\b", options: [.caseInsensitive]),
]

private func normalizeText(_ value: String?) -> String {
    getNormalizer().canonicalKey(value)
}

private func extractDayName(_ value: String?) -> String? {
    let upper = (value ?? "").uppercased()
    for day in ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"] where upper.contains(day) {
        return day
    }
    return nil
}

private func isFortPseudoExercise(_ value: String) -> Bool {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
        return false
    }
    for pattern in fortPseudoExercisePatterns where pattern.firstMatch(in: normalized, options: [], range: fullRange(of: normalized)) != nil {
        return true
    }
    return false
}

private func parsePlanEntries(_ planText: String) -> [PlanEntry] {
    var entries: [PlanEntry] = []
    var currentDay: String?

    for line in planText.components(separatedBy: .newlines) {
        if let dayMatch = dayRegex.firstMatch(in: line, options: [], range: fullRange(of: line)),
           let dayRange = Range(dayMatch.range(at: 1), in: line) {
            currentDay = extractDayName(String(line[dayRange]))
            continue
        }

        if let exerciseMatch = exerciseRegex.firstMatch(in: line, options: [], range: fullRange(of: line)),
           let exerciseRange = Range(exerciseMatch.range(at: 1), in: line) {
            let exercise = String(line[exerciseRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(
                PlanEntry(
                    day: currentDay,
                    exercise: exercise,
                    normalizedExercise: normalizeText(exercise),
                    prescriptionLine: "",
                    sets: nil,
                    reps: nil,
                    load: nil,
                    rest: "",
                    notes: ""
                )
            )
            continue
        }

        guard !entries.isEmpty else {
            continue
        }

        let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
        var current = entries.removeLast()

        if stripped.hasPrefix("- **Rest:**") {
            current = PlanEntry(
                day: current.day,
                exercise: current.exercise,
                normalizedExercise: current.normalizedExercise,
                prescriptionLine: current.prescriptionLine,
                sets: current.sets,
                reps: current.reps,
                load: current.load,
                rest: stripped,
                notes: current.notes
            )
            entries.append(current)
            continue
        }

        if stripped.hasPrefix("- **Notes:**") {
            current = PlanEntry(
                day: current.day,
                exercise: current.exercise,
                normalizedExercise: current.normalizedExercise,
                prescriptionLine: current.prescriptionLine,
                sets: current.sets,
                reps: current.reps,
                load: current.load,
                rest: current.rest,
                notes: stripped
            )
            entries.append(current)
            continue
        }

        if let match = prescriptionRegex.firstMatch(in: stripped, options: [], range: fullRange(of: stripped)),
           let setsRange = Range(match.range(at: 1), in: stripped),
           let repsRange = Range(match.range(at: 2), in: stripped),
           let loadRange = Range(match.range(at: 3), in: stripped) {
            let sets = Int(stripped[setsRange])
            let reps = String(stripped[repsRange])
            let load = Double(stripped[loadRange])
            current = PlanEntry(
                day: current.day,
                exercise: current.exercise,
                normalizedExercise: current.normalizedExercise,
                prescriptionLine: stripped,
                sets: sets,
                reps: reps,
                load: load,
                rest: current.rest,
                notes: current.notes
            )
            entries.append(current)
            continue
        }

        entries.append(current)
    }

    return entries
}

private func isMainPlateLift(_ name: String) -> Bool {
    getNormalizer().isMainPlateLift(name)
}

private func isDBExercise(_ name: String) -> Bool {
    getNormalizer().isDBExercise(name)
}

private func identifyTricepsAttachment(_ name: String) -> String {
    let value = normalizeText(name)
    if value.contains("single arm") && value.contains("d handle") {
        return "single_arm_d_handle"
    }
    if value.contains("d handle") {
        return "d_handle"
    }
    if value.contains("rope") {
        return "rope"
    }
    if value.contains("ez bar") {
        return "ez_bar"
    }
    if value.contains("straight bar") {
        return "straight_bar"
    }
    if value.contains("v bar") {
        return "v_bar"
    }
    if value.contains("bar") {
        return "bar"
    }
    return "other"
}

private func identifyBicepsGrip(_ entry: PlanEntry) -> String {
    let value = normalizeText(entry.exercise)
    let notes = normalizeText(entry.notes)

    let explicitPattern = makeRegex("\\b(supinated|pronated|neutral)\\s+grip\\b")
    for text in [value, notes] {
        if let match = explicitPattern.firstMatch(in: text, options: [], range: fullRange(of: text)),
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range])
        }
    }

    if value.contains("pronated") || value.contains("pronation") || value.contains("reverse curl") {
        return "pronated"
    }
    if value.contains("neutral") || value.contains("hammer") {
        return "neutral"
    }
    if value.contains("supinated") || value.contains("supination") {
        return "supinated"
    }

    var noteSignals: Set<String> = []
    if notes.contains("pronated") || notes.contains("pronation") || notes.contains("reverse curl") {
        noteSignals.insert("pronated")
    }
    if notes.contains("neutral") || notes.contains("hammer") {
        noteSignals.insert("neutral")
    }
    if notes.contains("supinated") || notes.contains("supination") {
        noteSignals.insert("supinated")
    }

    if noteSignals.count == 1 {
        return noteSignals.first ?? ""
    }

    return ""
}

private func addViolation(
    _ violations: inout [PlanViolation],
    code: String,
    message: String,
    day: String? = nil,
    exercise: String? = nil
) {
    violations.append(
        PlanViolation(
            code: code,
            message: message,
            day: day ?? "",
            exercise: exercise ?? ""
        )
    )
}

public func validatePlan(_ planText: String, progressionDirectives: [ProgressionDirective] = []) -> PlanValidationResult {
    let entries = parsePlanEntries(planText)
    var violations: [PlanViolation] = []

    for entry in entries {
        let exercise = entry.exercise
        let day = entry.day
        let prescription = entry.prescriptionLine

        if isFortPseudoExercise(exercise) {
            addViolation(
                &violations,
                code: "fort_header_as_exercise",
                message: "Fort section header/noise appeared as an exercise entry: \(exercise)",
                day: day,
                exercise: exercise
            )
        }

        if !prescription.isEmpty && rangeRegex.firstMatch(in: prescription, options: [], range: fullRange(of: prescription)) != nil {
            addViolation(
                &violations,
                code: "range_in_prescription",
                message: "Range found in prescription line: \(prescription)",
                day: day,
                exercise: exercise
            )
        }

        if isDBExercise(exercise), !isMainPlateLift(exercise), let load = entry.load {
            let rounded = Int(round(load))
            if abs(load - Double(rounded)) < 1e-9, rounded % 2 != 0 {
                addViolation(
                    &violations,
                    code: "odd_db_load",
                    message: "Odd dumbbell load detected: \(load) kg",
                    day: day,
                    exercise: exercise
                )
            }
        }

        // Split squats are forbidden on supplemental days only.
        // Fort-trainer-programmed split squats on Mon/Wed/Fri are permitted.
        let isFortDay = ["MONDAY", "WEDNESDAY", "FRIDAY"].contains(where: { day?.contains($0) == true })
        if normalizeText(exercise).contains("split squat"), !isFortDay {
            addViolation(
                &violations,
                code: "forbidden_split_squat",
                message: "Split squat detected on supplemental day — forbidden.",
                day: day,
                exercise: exercise
            )
        }

        if normalizeText(exercise).contains("carry") && day != "TUESDAY" {
            addViolation(
                &violations,
                code: "carry_wrong_day",
                message: "Carry exercise appears outside Tuesday.",
                day: day,
                exercise: exercise
            )
        }
    }

    let supplementalDays = ["TUESDAY", "THURSDAY", "SATURDAY"]
    for day in supplementalDays {
        let dayEntries = entries.filter { $0.day == day }
        if dayEntries.isEmpty {
            addViolation(
                &violations,
                code: "supplemental_day_missing",
                message: "Supplemental day \(day) is missing from generated plan.",
                day: day
            )
            continue
        }
        if dayEntries.count < 5 {
            addViolation(
                &violations,
                code: "supplemental_day_underfilled",
                message: "Supplemental day \(day) has only \(dayEntries.count) exercise(s); minimum expected is 5.",
                day: day
            )
        }

        let hasMcGill = dayEntries.contains { entry in
            let n = normalizeText(entry.exercise)
            return n.contains("mcgill") || (n.contains("big") && n.contains("3"))
        }
        if !hasMcGill {
            addViolation(
                &violations,
                code: "missing_mcgill_big3",
                message: "Supplemental day \(day) is missing McGill Big-3 (curl-up, side bridge, bird-dog).",
                day: day
            )
        }
    }

    let tricepsEntries = entries.filter { entry in
        guard let day = entry.day else {
            return false
        }
        return ["TUESDAY", "FRIDAY", "SATURDAY"].contains(where: { day.contains($0) }) && normalizeText(entry.exercise).contains("tricep")
    }

    if !tricepsEntries.isEmpty {
        var attachments: [(String, String, String)] = []

        for entry in tricepsEntries {
            let attachment = identifyTricepsAttachment(entry.exercise)
            attachments.append((entry.day ?? "", entry.exercise, attachment))

            if entry.day == "SATURDAY", attachment == "single_arm_d_handle" {
                addViolation(
                    &violations,
                    code: "single_arm_d_handle_saturday",
                    message: "Single-arm D-handle triceps work is not allowed on Saturday.",
                    day: entry.day,
                    exercise: entry.exercise
                )
            }
        }

        let uniqueAttachments = Set(attachments.map { $0.2 })
        if uniqueAttachments.count < 2 {
            addViolation(
                &violations,
                code: "triceps_attachment_rotation",
                message: "Triceps attachments are not varied across Tue/Fri/Sat."
            )
        }
    }

    var gripByDay: [String: String] = [:]
    let dayOrder = ["TUESDAY", "THURSDAY", "SATURDAY"]

    for day in dayOrder {
        let dayEntries = entries.filter { entry in
            entry.day == day && normalizeText(entry.exercise).contains("curl")
        }

        if dayEntries.isEmpty {
            continue
        }

        var grip = ""
        for dayEntry in dayEntries {
            grip = identifyBicepsGrip(dayEntry)
            if !grip.isEmpty {
                break
            }
        }

        if !grip.isEmpty {
            gripByDay[day] = grip
        }
    }

    var previousDay: String?
    var previousGrip: String?
    for day in dayOrder {
        guard let grip = gripByDay[day] else {
            continue
        }

        if let previousGrip, previousGrip == grip {
            addViolation(
                &violations,
                code: "biceps_grip_repeat",
                message: "Biceps grip repeats on consecutive supplemental days (\(previousDay ?? "") -> \(day)): \(grip)."
            )
        }

        previousDay = day
        previousGrip = grip
    }

    let normalizer = getNormalizer()

    for directive in progressionDirectives where directive.holdLock {
        let targetDay = extractDayName(directive.dayName)
        guard
            let targetDay,
            let targetLoad = directive.targetLoad,
            let targetReps = directive.targetReps
        else {
            continue
        }

        var match: PlanEntry?

        for entry in entries {
            guard entry.day == targetDay else {
                continue
            }
            if normalizer.areSameExercise(directive.exerciseName, entry.exercise) {
                match = entry
                break
            }
        }

        guard let match else {
            continue
        }

        let loadMismatch = match.load == nil || abs((match.load ?? 0) - targetLoad) > 1e-9
        let repsMismatch = (match.reps ?? "").trimmingCharacters(in: .whitespacesAndNewlines) != targetReps

        if loadMismatch || repsMismatch {
            addViolation(
                &violations,
                code: "hold_lock_violation",
                message: "Hold-lock not respected for \(directive.exerciseName): expected \(targetReps) reps @ \(targetLoad) kg.",
                day: match.day,
                exercise: match.exercise
            )
        }
    }

    let summary: String
    if !entries.isEmpty {
        summary = "Validation: \(entries.count) exercises checked, \(violations.count) violation(s)."
    } else {
        summary = "Validation: no exercises parsed from plan."
    }

    return PlanValidationResult(entries: entries, violations: violations, summary: summary)
}
