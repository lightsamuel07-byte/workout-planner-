import Foundation

public struct FortSectionExercise: Equatable, Sendable {
    public let block: String
    public let exercise: String
    public let sectionID: String
    public let sectionLabel: String
    public let rawHeader: String

    public init(block: String, exercise: String, sectionID: String, sectionLabel: String, rawHeader: String) {
        self.block = block
        self.exercise = exercise
        self.sectionID = sectionID
        self.sectionLabel = sectionLabel
        self.rawHeader = rawHeader
    }
}

public struct FortCompiledSection: Equatable, Sendable {
    public let sectionID: String
    public let sectionLabel: String
    public let rawHeader: String
    public let blockLetter: String
    public let exercises: [FortSectionExercise]

    public init(sectionID: String, sectionLabel: String, rawHeader: String, blockLetter: String, exercises: [FortSectionExercise]) {
        self.sectionID = sectionID
        self.sectionLabel = sectionLabel
        self.rawHeader = rawHeader
        self.blockLetter = blockLetter
        self.exercises = exercises
    }
}

public struct FortParsedSection: Equatable, Sendable {
    public let sectionID: String
    public let sectionLabel: String
    public let blockHint: String
    public let rawHeader: String
    public let exercises: [String]
    /// True when the section type was inferred dynamically (not matched by a static rule).
    public let isInferred: Bool

    public init(sectionID: String, sectionLabel: String, blockHint: String, rawHeader: String, exercises: [String], isInferred: Bool = false) {
        self.sectionID = sectionID
        self.sectionLabel = sectionLabel
        self.blockHint = blockHint
        self.rawHeader = rawHeader
        self.exercises = exercises
        self.isInferred = isInferred
    }
}

public struct FortParsedDay: Equatable, Sendable {
    public let day: String
    public let dateLine: String
    public let titleLine: String
    public let sections: [FortParsedSection]
    public let compiledSections: [FortCompiledSection]
    public let compiledTemplate: String
    public let totalExercises: Int
    public let confidence: Double
    public let warnings: [String]

    public init(
        day: String,
        dateLine: String,
        titleLine: String,
        sections: [FortParsedSection],
        compiledSections: [FortCompiledSection],
        compiledTemplate: String,
        totalExercises: Int,
        confidence: Double,
        warnings: [String]
    ) {
        self.day = day
        self.dateLine = dateLine
        self.titleLine = titleLine
        self.sections = sections
        self.compiledSections = compiledSections
        self.compiledTemplate = compiledTemplate
        self.totalExercises = totalExercises
        self.confidence = confidence
        self.warnings = warnings
    }
}

public struct FortCompilerMetadata: Equatable, Sendable {
    public let overallConfidence: Double
    public let days: [FortParsedDay]

    public init(overallConfidence: Double, days: [FortParsedDay]) {
        self.overallConfidence = overallConfidence
        self.days = days
    }
}

public struct FortFidelityViolation: Equatable, Sendable, ViolationDescribing {
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

public struct FortFidelityResult: Equatable, Sendable {
    public let violations: [FortFidelityViolation]
    public let summary: String
    public let expectedAnchors: Int
    public let matchedAnchors: Int

    public init(violations: [FortFidelityViolation], summary: String, expectedAnchors: Int, matchedAnchors: Int) {
        self.violations = violations
        self.summary = summary
        self.expectedAnchors = expectedAnchors
        self.matchedAnchors = matchedAnchors
    }
}

public struct FortRepairInsertion: Equatable, Sendable {
    public let day: String
    public let sectionID: String
    public let exercise: String
    public let block: String

    public init(day: String, sectionID: String, exercise: String, block: String) {
        self.day = day
        self.sectionID = sectionID
        self.exercise = exercise
        self.block = block
    }
}

public struct FortRepairSummary: Equatable, Sendable {
    public let inserted: Int
    public let insertions: [FortRepairInsertion]
    public let dropped: Int
    public let rebuiltDays: Int
    public let summary: String

    public init(inserted: Int, insertions: [FortRepairInsertion], dropped: Int, rebuiltDays: Int, summary: String) {
        self.inserted = inserted
        self.insertions = insertions
        self.dropped = dropped
        self.rebuiltDays = rebuiltDays
        self.summary = summary
    }
}

public struct PlanFortEntry: Equatable, Sendable {
    public let day: String
    public let block: String
    public let blockRank: Int?
    public let exercise: String
    public let load: Double?
    public let reps: String?
    public let notes: String

    public init(day: String, block: String, blockRank: Int?, exercise: String, load: Double?, reps: String?, notes: String) {
        self.day = day
        self.block = block
        self.blockRank = blockRank
        self.exercise = exercise
        self.load = load
        self.reps = reps
        self.notes = notes
    }
}

private struct SectionRule {
    let sectionID: String
    let sectionLabel: String
    let blockHint: String
    let patterns: [NSRegularExpression]
}

private struct MutableSection {
    let sectionID: String
    let sectionLabel: String
    let blockHint: String
    let rawHeader: String
    var exercises: [String]
    var isInferred: Bool = false
}

private struct DaySegment {
    let day: String
    var lines: [String]
}

private struct DayEntrySpan {
    let startIndex: Int
    let endIndex: Int
    let block: String
    let blockLetter: String
    let blockIndex: Int
    let blockRank: Int?
    let exercise: String
}

private struct WorkingDayEntry {
    let span: DayEntrySpan
    let lines: [String]
    var used: Bool
}

private let planDayRegex = makeRegex("^\\s*##\\s+([A-Z]+DAY)\\b", options: [.caseInsensitive])
private let planExerciseRegex = makeRegex("^\\s*###\\s+([A-Z]\\d+)\\.\\s*(.+)$", options: [.caseInsensitive])
private let planPrescriptionRegex = makeRegex("^\\s*-\\s*(\\d+)\\s*x\\s*(.+?)\\s*@\\s*(.+)$", options: [.caseInsensitive])

private let nonExercisePatterns: [NSRegularExpression] = [
    makeRegex("^TIPS?\\b", options: [.caseInsensitive]),
    makeRegex("^REST\\b", options: [.caseInsensitive]),
    makeRegex("^RIGHT\\s+INTO\\b", options: [.caseInsensitive]),
    makeRegex("^START\\s+WITH\\b", options: [.caseInsensitive]),
    makeRegex("^THIS\\s+IS\\b", options: [.caseInsensitive]),
    makeRegex("^YOU\\s+ARE\\b", options: [.caseInsensitive]),
    makeRegex("^OPTIONAL\\b", options: [.caseInsensitive]),
    makeRegex("^REMINDER\\b", options: [.caseInsensitive]),
    makeRegex("^NUMBER\\s+OF\\s+REPS\\b", options: [.caseInsensitive]),
    makeRegex("^WRITE\\s+NOTES\\b", options: [.caseInsensitive]),
    makeRegex("^HIP\\s+CIRCLE\\s+IS\\s+OPTIONAL\\b", options: [.caseInsensitive]),
    makeRegex("^\\d+\\s*SECONDS?\\s+AT\\s+\\d+(?:\\.\\d+)?\\b", options: [.caseInsensitive]),
]

private let metadataExact: Set<String> = [
    "TIPS", "TIPS HISTORY", "HISTORY", "COMPLETE", "RX", "REPS", "WEIGHT", "TIME",
    "TIME (MM:SS)", "HEIGHT (IN)", "DIST. (M)", "DIST. (MILES)", "DIST (MILES)",
    "DISTANCE (MILES)", "DIST. (MI)", "METERS", "WATTS", "OTHER NUMBER", "SETS",
    "EXAMPLES",
]

private let metadataRegexes: [NSRegularExpression] = [
    makeRegex("^\\d+\\s*(SETS?|REPS?)$", options: [.caseInsensitive]),
    makeRegex("^\\d+(?:\\.\\d+)?%$", options: [.caseInsensitive]),
    makeRegex("^\\d+(?:\\.\\d+)?$", options: [.caseInsensitive]),
    makeRegex("^\\d{1,2}:\\d{2}(?:\\.\\d+)?$", options: [.caseInsensitive]),
    makeRegex("^(REPS?|WEIGHT|TIME|TIME\\s*\\(MM:SS\\)|HEIGHT\\s*\\(IN\\)|DIST\\.?\\s*\\((M|MI|MILES)\\)|DISTANCE\\s*\\(MILES\\)|WATTS|OTHER NUMBER|METERS|RX)$", options: [.caseInsensitive]),
]

private let sectionRules: [SectionRule] = [
    SectionRule(
        sectionID: "conditioning",
        sectionLabel: "Conditioning/THAW",
        blockHint: "F",
        patterns: [
            "\\bTHAW\\b",
            "\\bREDEMPTION\\b",
            "\\bFINISHER\\b",
            "\\bCONDITIONING\\b",
            "\\bCONDITIONING\\s+TEST\\b",
            "\\bGARAGE\\b.*\\b(?:ROW|BIKE|BIKEERG|RUN|SKI|ERG|MILE)\\b",
            "\\b(?:\\d+\\s*K|\\d+\\s*MILE)\\b.*\\b(?:ROW|BIKE|BIKEERG|RUN|SKI|ERG)\\b.*\\bTEST\\b",
        ].map { makeRegex($0, options: [.caseInsensitive]) }
    ),
    SectionRule(
        sectionID: "strength_backoff",
        sectionLabel: "Strength Back-Offs",
        blockHint: "D",
        patterns: [
            "\\bBACK[\\s\\-]*OFFS?\\b",
        ].map { makeRegex($0, options: [.caseInsensitive]) }
    ),
    SectionRule(
        sectionID: "strength_build",
        sectionLabel: "Strength Build-Up/Warm-Up",
        blockHint: "B",
        patterns: [
            "\\bCLUSTER\\s+WARM\\s*UP\\b",
            "\\bBUILD\\s*UP\\b",
            "\\bRAMP\\b",
            "\\bCALIBRATION\\b",
            "\\bPULL[\\s\\-]*UPS?\\s+EVERY\\s+DAY\\b",
        ].map { makeRegex($0, options: [.caseInsensitive]) }
    ),
    SectionRule(
        sectionID: "power_activation",
        sectionLabel: "Power/Activation",
        blockHint: "B",
        patterns: [
            "\\bFANNING\\s+THE\\s+FLAMES\\b",
            "\\bPOWER\\b",
            "\\bREACTIVITY\\b",
        ].map { makeRegex($0, options: [.caseInsensitive]) }
    ),
    SectionRule(
        sectionID: "auxiliary_hypertrophy",
        sectionLabel: "Auxiliary/Hypertrophy",
        blockHint: "E",
        patterns: [
            "\\bAUXILIARY\\b",
            "\\bIT\\s+BURNS\\b",
            "\\bMYO\\s*REP\\b",
            "\\bACCESSORY\\b",
            "\\bUPPER\\s+BODY\\s+AUX\\b",
            "\\bLOWER\\s+BODY\\s+AUX\\b",
            "\\bAUXILIARY/RECOVERY\\b",
            "\\bTHE\\s+PAY\\s+OFF\\b",
            "\\bPAY\\s*OFF\\b",
        ].map { makeRegex($0, options: [.caseInsensitive]) }
    ),
    SectionRule(
        sectionID: "strength_work",
        sectionLabel: "Main Strength/Breakpoint",
        blockHint: "C",
        patterns: [
            "\\bCLUSTER\\s+SET\\b",
            "\\bWORKING\\s+SET\\b",
            "\\bBARBELL\\s+BREAKPOINT\\b",
            "\\bDUMBBELL\\s+BREAKPOINT\\b",
            "\\bBODYWEIGHT\\s+BREAKPOINT\\b",
            "\\bBREAKPOINT\\b",
            "\\bCAULDRON\\b",
            "\\b(?:1|3)\\s*RM\\s+TEST\\b",
            "\\bMAX\\s+PULL[\\s\\-]*UP\\s+TEST\\b",
            "\\bMAX\\s+PUSH[\\s\\-]*UP\\s+TEST\\b",
            "\\bTHE\\s+REPLACEMENTS\\b",
            "\\bTHE\\s+SWEAT\\s+BANK\\b",
        ].map { makeRegex($0, options: [.caseInsensitive]) }
    ),
    SectionRule(
        sectionID: "prep_mobility",
        sectionLabel: "Prep/Mobility",
        blockHint: "A",
        patterns: [
            "\\bIGNITION\\b",
            "\\bPREP\\b",
            "\\bWARM\\s*UP\\b",
            "\\bTARGETED\\s+WARM[\\s\\-]*UP\\b",
            "\\bACTIVATION\\b",
            "\\bKOT\\s+WARM[\\s\\-]*UP\\b",
            "\\bPREPARE\\s+TO\\s+ENGAGE\\b",
        ].map { makeRegex($0, options: [.caseInsensitive]) }
    ),
]

private let numericTokenRegex = makeRegex("[-+]?\\d+(?:\\.\\d+)?")

private func parsePrescriptionLine(_ line: String) -> (sets: Int?, reps: String?, load: Double?)? {
    let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let match = planPrescriptionRegex.firstMatch(in: stripped, options: [], range: fullRange(of: stripped)),
          let setsRange = Range(match.range(at: 1), in: stripped),
          let repsRange = Range(match.range(at: 2), in: stripped),
          let loadRange = Range(match.range(at: 3), in: stripped)
    else {
        return nil
    }

    let sets = Int(stripped[setsRange])
    let repsRaw = String(stripped[repsRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    let loadRaw = String(stripped[loadRange]).trimmingCharacters(in: .whitespacesAndNewlines)

    let normalizedReps = repsRaw
        .replacingOccurrences(
            of: "\\b(reps?|seconds?|secs?|minutes?|mins?|meters?|miles?)\\b",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    var parsedLoad: Double?
    if let loadMatch = numericTokenRegex.firstMatch(in: loadRaw, options: [], range: fullRange(of: loadRaw)),
       let numberRange = Range(loadMatch.range(at: 0), in: loadRaw) {
        parsedLoad = Double(loadRaw[numberRange])
    }

    let reps = normalizedReps.isEmpty ? repsRaw : normalizedReps
    return (sets, reps.isEmpty ? nil : reps, parsedLoad)
}

private func fcCollapseWhitespace(_ value: String) -> String {
    value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

private func normalizeSpace(_ value: String?) -> String {
    fcCollapseWhitespace((value ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
}

private func isMostlyUpper(_ value: String) -> Bool {
    let chars = value.filter { $0.isLetter }
    guard chars.count >= 3 else {
        return false
    }
    let upper = chars.filter { $0.isUppercase }.count
    return Double(upper) / Double(chars.count) >= 0.6
}

private func isNarrativeLine(_ value: String) -> Bool {
    let words = value.split(separator: " ")
    let chars = value.filter { $0.isLetter }
    guard words.count > 6, chars.count >= 12 else {
        return false
    }
    let lower = chars.filter { $0.isLowercase }.count
    return Double(lower) / Double(chars.count) > 0.35
}

private func matchSectionRule(_ value: String) -> SectionRule? {
    let normalized = normalizeSpace(value)
    guard !normalized.isEmpty, isMostlyUpper(normalized) else {
        return nil
    }
    let words = normalized.split(separator: " ")
    if words.count > 12 {
        return nil
    }
    if normalized.hasSuffix(".") && words.count > 6 {
        return nil
    }

    for rule in sectionRules {
        for pattern in rule.patterns where pattern.firstMatch(in: normalized, options: [], range: fullRange(of: normalized)) != nil {
            return rule
        }
    }
    return nil
}

private func canonicalSectionDefinition(_ sectionID: String) -> (sectionLabel: String, blockHint: String) {
    switch sectionID {
    case "prep_mobility":
        return ("Prep/Mobility", "A")
    case "power_activation":
        return ("Power/Activation", "B")
    case "strength_build":
        return ("Strength Build-Up/Warm-Up", "B")
    case "strength_work":
        return ("Main Strength/Breakpoint", "C")
    case "strength_backoff":
        return ("Strength Back-Offs", "D")
    case "auxiliary_hypertrophy":
        return ("Auxiliary/Hypertrophy", "E")
    case "conditioning":
        return ("Conditioning/THAW", "F")
    default:
        return ("Dynamic Section", "Z")
    }
}

private func isPotentialSectionHeader(_ value: String) -> Bool {
    let normalized = normalizeSpace(value)
    guard !normalized.isEmpty else {
        return false
    }
    if matchSectionRule(normalized) != nil {
        return true
    }
    if isMetadataLine(normalized) || isNarrativeLine(normalized) {
        return false
    }
    if nonExercisePatterns.contains(where: { $0.firstMatch(in: normalized, options: [], range: fullRange(of: normalized)) != nil }) {
        return false
    }

    let words = normalized.split(separator: " ")
    if words.count < 2 || words.count > 8 {
        return false
    }
    if !isMostlyUpper(normalized) {
        return false
    }

    let upper = normalized.uppercased()
    if makeRegex("\\b(MONDAY|TUESDAY|WEDNESDAY|THURSDAY|FRIDAY|SATURDAY|SUNDAY)\\b", options: [.caseInsensitive]).firstMatch(in: upper, options: [], range: fullRange(of: upper)) != nil,
       makeRegex("\\d").firstMatch(in: normalized, options: [], range: fullRange(of: normalized)) != nil {
        return false
    }

    return true
}

private func inferDynamicSectionID(header: String, exercises: [String], index: Int, total: Int, usedIDs: Set<String>) -> String {
    let joinedUpper = ([header] + exercises).joined(separator: " ").uppercased()
    let normalizedExercises = exercises.map(normalizeExerciseName)

    let hasConditioningCue = makeRegex("\\b(ROWERG|SKIERG|BIKEERG|FAN\\s*BIKE|AIR\\s*BIKE|ASSAULT\\s*BIKE|TREADMILL|RUN|ERG|AEROBIC|THAW|CONDITIONING|REDEMPTION|MILE|METCON|\\d+\\s*K\\s*ROW)\\b", options: [.caseInsensitive]).firstMatch(
        in: joinedUpper,
        options: [],
        range: fullRange(of: joinedUpper)
    ) != nil

    let hasPullUpCue = makeRegex("\\b(PULL\\s*UP|CHIN\\s*UP|SCAP\\s*PULL)\\b", options: [.caseInsensitive]).firstMatch(
        in: joinedUpper,
        options: [],
        range: fullRange(of: joinedUpper)
    ) != nil

    let hasMobilityCue = makeRegex("\\b(SYMMETRY|ROTATION|MOBILITY|TKE|TERMINAL\\s*KNEE|ACTIVATION|WARM\\s*UP|PREP|THORACIC|DEADBUG|ARCHER)\\b", options: [.caseInsensitive]).firstMatch(
        in: joinedUpper,
        options: [],
        range: fullRange(of: joinedUpper)
    ) != nil

    let hasMainLiftCue = normalizedExercises.contains(where: { name in
        name.contains("squat") || name.contains("deadlift") || name.contains("bench press") || name.contains("strict press")
    })

    let hasAccessoryCue = normalizedExercises.contains(where: { name in
        name.contains("row") || name.contains("curl") || name.contains("press") || name.contains("rdl") || name.contains("raise") || name.contains("rollout")
    }) || exercises.count >= 2

    if hasConditioningCue {
        return "conditioning"
    }
    if hasMainLiftCue {
        return "strength_work"
    }
    if hasPullUpCue {
        return "strength_build"
    }
    if hasMobilityCue, !hasAccessoryCue {
        return "prep_mobility"
    }
    if hasAccessoryCue, !hasMobilityCue {
        return "auxiliary_hypertrophy"
    }

    let denominator = max(total - 1, 1)
    let relativePosition = Double(index) / Double(denominator)
    if relativePosition <= 0.25, !usedIDs.contains("prep_mobility") {
        return "prep_mobility"
    }
    if relativePosition >= 0.75, !usedIDs.contains("conditioning") {
        return "conditioning"
    }
    if !usedIDs.contains("strength_work") {
        return "strength_work"
    }
    if !usedIDs.contains("auxiliary_hypertrophy") {
        return "auxiliary_hypertrophy"
    }
    return "strength_build"
}

private func normalizeDynamicSections(_ sections: [MutableSection]) -> [MutableSection] {
    guard !sections.isEmpty else {
        return []
    }

    var normalized = sections
    var usedIDs = Set(
        normalized
            .map(\.sectionID)
            .filter { $0 != "dynamic_unknown" }
    )

    for index in normalized.indices where normalized[index].sectionID == "dynamic_unknown" {
        let inferredID = inferDynamicSectionID(
            header: normalized[index].rawHeader,
            exercises: normalized[index].exercises,
            index: index,
            total: normalized.count,
            usedIDs: usedIDs
        )
        let canonical = canonicalSectionDefinition(inferredID)
        normalized[index] = MutableSection(
            sectionID: inferredID,
            sectionLabel: canonical.sectionLabel,
            blockHint: canonical.blockHint,
            rawHeader: normalized[index].rawHeader,
            exercises: normalized[index].exercises,
            isInferred: true  // Mark as dynamically inferred — user may want to correct
        )
        usedIDs.insert(inferredID)
    }

    return normalized
}

public func findFirstSectionIndex(lines: [String]) -> Int? {
    guard !lines.isEmpty else {
        return nil
    }
    let maxCount = min(lines.count, 400)
    for index in 0..<maxCount {
        if matchSectionRule(lines[index]) != nil || isPotentialSectionHeader(lines[index]) {
            return index
        }
    }
    return nil
}

private func isMetadataLine(_ value: String) -> Bool {
    let normalized = normalizeSpace(value)
    if normalized.isEmpty {
        return true
    }

    let upper = normalized.uppercased()
    if metadataExact.contains(upper) {
        return true
    }

    for pattern in metadataRegexes where pattern.firstMatch(in: normalized, options: [], range: fullRange(of: normalized)) != nil {
        return true
    }

    return false
}

private func isExerciseCandidate(_ value: String) -> Bool {
    let normalized = normalizeSpace(value)
    guard !normalized.isEmpty else {
        return false
    }
    if matchSectionRule(normalized) != nil {
        return false
    }
    if isMetadataLine(normalized) {
        return false
    }
    if nonExercisePatterns.contains(where: { $0.firstMatch(in: normalized, options: [], range: fullRange(of: normalized)) != nil }) {
        return false
    }
    if isNarrativeLine(normalized) {
        return false
    }
    if normalized.hasSuffix(":") && normalized.split(separator: " ").count <= 6 {
        return false
    }
    if normalized.count > 80 {
        return false
    }
    if normalized.contains(":"), normalized.split(separator: " ").count > 4 {
        return false
    }
    if normalized.rangeOfCharacter(from: .letters) == nil {
        return false
    }
    return true
}

private func shouldSeedSectionHeaderAsExercise(sectionID: String, headerLine: String) -> Bool {
    guard sectionID == "conditioning" else {
        return false
    }
    let normalized = normalizeSpace(headerLine).uppercased()
    guard normalized.contains("TEST") || normalized.contains("GARAGE") else {
        return false
    }
    return makeRegex("\\b(ROW|BIKE|BIKEERG|RUN|SKI|ERG|MILE)\\b", options: [.caseInsensitive])
        .firstMatch(in: normalized, options: [], range: fullRange(of: normalized)) != nil
}

private func extractDayHeader(_ lines: [String]) -> (String, String) {
    let nonEmpty = lines.map { normalizeSpace($0) }.filter { !$0.isEmpty }
    guard !nonEmpty.isEmpty else {
        return ("", "")
    }

    var dateLine = ""
    var titleLine = ""

    for line in nonEmpty.prefix(8) {
        let upper = line.uppercased()
        if dateLine.isEmpty,
           makeRegex("\\b(MONDAY|TUESDAY|WEDNESDAY|THURSDAY|FRIDAY|SATURDAY|SUNDAY)\\b", options: [.caseInsensitive]).firstMatch(in: upper, options: [], range: fullRange(of: upper)) != nil,
           makeRegex("\\d").firstMatch(in: line, options: [], range: fullRange(of: line)) != nil {
            dateLine = line
            continue
        }

        if titleLine.isEmpty,
           matchSectionRule(line) == nil,
           line.split(separator: " ").count <= 12 {
            titleLine = line
        }
    }

    return (dateLine, titleLine)
}

private func sectionBaseRank(_ sectionID: String) -> Int {
    let mapping: [String: Int] = [
        "prep_mobility": 1,
        "power_activation": 2,
        "strength_build": 2,
        "strength_work": 3,
        "strength_backoff": 4,
        "auxiliary_hypertrophy": 5,
        "conditioning": 6,
    ]
    return mapping[sectionID] ?? 6
}

private func rankToLetter(_ rank: Int) -> String {
    let bounded = max(1, min(rank, 26))
    guard let scalar = UnicodeScalar(64 + bounded) else {
        return "Z"
    }
    return String(Character(scalar))
}

private func normalizeExerciseName(_ value: String?) -> String {
    let lower = (value ?? "").lowercased()
    let replaced = lower.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
    return replaced.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func extractDayName(_ value: String?) -> String? {
    let upper = (value ?? "").uppercased()
    for day in ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"] where upper.contains(day) {
        return day
    }
    return nil
}

private func isMainLiftName(_ value: String) -> Bool {
    let normalized = normalizeExerciseName(value)
    if " \(normalized) ".contains(" db ") || normalized.contains("dumbbell") {
        return false
    }
    return ["squat", "deadlift", "bench press", "chest press"].contains { normalized.contains($0) }
}

private func blockRank(_ blockLabel: String) -> Int? {
    guard let first = blockLabel.first else {
        return nil
    }
    let letter = String(first).uppercased()
    guard let scalar = letter.unicodeScalars.first else {
        return nil
    }
    let value = Int(scalar.value)
    guard value >= 65, value <= 90 else {
        return nil
    }
    return value - 64
}

private func weekdayRank(_ dayName: String) -> Int {
    let mapping: [String: Int] = [
        "MONDAY": 1,
        "TUESDAY": 2,
        "WEDNESDAY": 3,
        "THURSDAY": 4,
        "FRIDAY": 5,
        "SATURDAY": 6,
        "SUNDAY": 7,
    ]
    return mapping[dayName.uppercased()] ?? 99
}

private func buildCompiledTemplates(_ sections: [FortParsedSection], maxExercisesPerSection: Int) -> [FortCompiledSection] {
    var sectionBlocks: [FortCompiledSection] = []
    var usedRanks: Set<Int> = []
    var currentRank = 1

    for section in sections {
        let selected = Array(section.exercises.prefix(maxExercisesPerSection))
        if selected.isEmpty {
            continue
        }

        let desiredRank = sectionBaseRank(section.sectionID)
        var rank = max(desiredRank, currentRank)
        while usedRanks.contains(rank), rank <= 26 {
            rank += 1
        }
        if rank > 26 {
            rank = min((usedRanks.max() ?? 1) + 1, 26)
        }
        usedRanks.insert(rank)
        currentRank = rank
        let letter = rankToLetter(rank)
        let exerciseBlocks = selected.enumerated().map { index, exerciseName in
            FortSectionExercise(
                block: "\(letter)\(index + 1)",
                exercise: exerciseName,
                sectionID: section.sectionID,
                sectionLabel: section.sectionLabel,
                rawHeader: section.rawHeader
            )
        }

        sectionBlocks.append(
            FortCompiledSection(
                sectionID: section.sectionID,
                sectionLabel: section.sectionLabel,
                rawHeader: section.rawHeader,
                blockLetter: letter,
                exercises: exerciseBlocks
            )
        )
    }

    return sectionBlocks
}

private func renderDayTemplate(day: String, titleLine: String, sections: [FortCompiledSection]) -> String {
    var lines: [String] = []
    let titleSuffix = titleLine.isEmpty ? "" : " (\(titleLine))"
    lines.append("## \(day.uppercased())\(titleSuffix)")

    for section in sections {
        for exercise in section.exercises {
            lines.append("### \(exercise.block). \(exercise.exercise)")
            lines.append("- Section: \(section.sectionLabel) | Header: \(section.rawHeader) | Prescription: preserve from Fort source.")
        }
        lines.append("")
    }

    while lines.last == "" {
        _ = lines.popLast()
    }

    return lines.joined(separator: "\n")
}

/// Parse a single Fort workout day.
/// - Parameter sectionOverrides: Maps rawHeader (uppercased) → sectionID for user-confirmed section types.
///   Overrides take priority over both static regex rules and dynamic inference.
public func parseFortDay(dayName: String, workoutText: String, sectionOverrides: [String: String] = [:]) -> FortParsedDay {
    let text = workoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    let lines = text.components(separatedBy: .newlines)
    let (dateLine, titleLine) = extractDayHeader(lines)

    var sections: [MutableSection] = []
    var warnings: [String] = []
    var currentSectionIndex: Int?
    var sawCompleteBoundary = false

    for raw in lines {
        var line = normalizeSpace(raw)
        if line.isEmpty {
            continue
        }

        if line.uppercased() == "COMPLETE" {
            sawCompleteBoundary = true
            continue
        }

        if line.uppercased().hasPrefix("COMPLETE ") {
            let maybeSection = normalizeSpace(String(line.dropFirst(9)))
            if matchSectionRule(maybeSection) != nil || isPotentialSectionHeader(maybeSection) {
                line = maybeSection
            }
        }

        // User-confirmed overrides take priority over everything else
        if let overrideSectionID = sectionOverrides[line.uppercased()],
           matchSectionRule(line) == nil || true {  // always prefer override
            let canonical = canonicalSectionDefinition(overrideSectionID)
            let section = MutableSection(
                sectionID: overrideSectionID,
                sectionLabel: canonical.sectionLabel,
                blockHint: canonical.blockHint,
                rawHeader: line,
                exercises: [],
                isInferred: false  // user-confirmed
            )
            sections.append(section)
            currentSectionIndex = sections.count - 1
            sawCompleteBoundary = false
            continue
        }

        if let rule = matchSectionRule(line) {
            var section = MutableSection(
                sectionID: rule.sectionID,
                sectionLabel: rule.sectionLabel,
                blockHint: rule.blockHint,
                rawHeader: line,
                exercises: []
            )

            if shouldSeedSectionHeaderAsExercise(sectionID: rule.sectionID, headerLine: line) {
                section.exercises.append(line)
            }

            sections.append(section)
            currentSectionIndex = sections.count - 1
            sawCompleteBoundary = false
            continue
        }

        if isPotentialSectionHeader(line), (currentSectionIndex == nil || sawCompleteBoundary) {
            let section = MutableSection(
                sectionID: "dynamic_unknown",
                sectionLabel: "Dynamic Section",
                blockHint: "Z",
                rawHeader: line,
                exercises: []
            )
            sections.append(section)
            currentSectionIndex = sections.count - 1
            sawCompleteBoundary = false
            continue
        }

        guard let currentSectionIndex else {
            continue
        }

        if isExerciseCandidate(line) {
            var section = sections[currentSectionIndex]
            let existing = Set(section.exercises.map { normalizeSpace($0).uppercased() })
            let dedupeKey = normalizeSpace(line).uppercased()
            if !existing.contains(dedupeKey) {
                section.exercises.append(line)
                sections[currentSectionIndex] = section
                sawCompleteBoundary = false
            }
        }
    }

    let normalizedSections = normalizeDynamicSections(sections)
    let parsedSections = normalizedSections.map {
        FortParsedSection(
            sectionID: $0.sectionID,
            sectionLabel: $0.sectionLabel,
            blockHint: $0.blockHint,
            rawHeader: $0.rawHeader,
            exercises: $0.exercises,
            isInferred: $0.isInferred
        )
    }

    let sectionCount = parsedSections.count
    let totalExercises = parsedSections.reduce(0) { $0 + $1.exercises.count }
    let presentSectionIDs = Set(parsedSections.map(\.sectionID))
    let coreIDs: Set<String> = ["prep_mobility", "strength_work", "auxiliary_hypertrophy", "conditioning"]
    let coverage = Double(presentSectionIDs.intersection(coreIDs).count) / Double(coreIDs.count)

    let sectionScore = min(1.0, Double(sectionCount) / 6.0)
    let exerciseScore = min(1.0, Double(totalExercises) / 14.0)
    let confidence = (0.45 * sectionScore) + (0.35 * exerciseScore) + (0.20 * coverage)
    let roundedConfidence = Double(round(confidence * 100) / 100)

    if sectionCount == 0 {
        warnings.append("No recognized section headers detected.")
    }
    if totalExercises == 0 && sectionCount > 0 {
        warnings.append("Sections found but no exercise anchors extracted.")
    }

    let compiledSections = buildCompiledTemplates(parsedSections, maxExercisesPerSection: 4)
    let compiledTemplate = renderDayTemplate(day: dayName, titleLine: titleLine, sections: compiledSections)

    return FortParsedDay(
        day: dayName,
        dateLine: dateLine,
        titleLine: titleLine,
        sections: parsedSections,
        compiledSections: compiledSections,
        compiledTemplate: compiledTemplate,
        totalExercises: totalExercises,
        confidence: roundedConfidence,
        warnings: warnings
    )
}

/// Build the full Fort compiler context string and metadata for generation.
/// - Parameter sectionOverrides: day → (rawHeader → sectionID) user-confirmed mappings.
public func buildFortCompilerContext(dayTextMap: [String: String], sectionOverrides: [String: [String: String]] = [:], maxExercisesPerSection: Int = 4) -> (String, FortCompilerMetadata) {
    var parsedDays: [FortParsedDay] = []
    let orderedDays = ["Monday", "Wednesday", "Friday"]

    for dayName in orderedDays {
        let dayOverrides = sectionOverrides[dayName] ?? [:]
        let parsed = parseFortDay(dayName: dayName, workoutText: dayTextMap[dayName] ?? "", sectionOverrides: dayOverrides)
        let compiledSections = buildCompiledTemplates(parsed.sections, maxExercisesPerSection: maxExercisesPerSection)
        let compiledTemplate = renderDayTemplate(day: parsed.day, titleLine: parsed.titleLine, sections: compiledSections)

        parsedDays.append(
            FortParsedDay(
                day: parsed.day,
                dateLine: parsed.dateLine,
                titleLine: parsed.titleLine,
                sections: parsed.sections,
                compiledSections: compiledSections,
                compiledTemplate: compiledTemplate,
                totalExercises: parsed.totalExercises,
                confidence: parsed.confidence,
                warnings: parsed.warnings
            )
        )
    }

    let confidences = parsedDays.filter { !$0.sections.isEmpty }.map(\.confidence)
    let overallConfidence = confidences.isEmpty ? 0.0 : Double(round((confidences.reduce(0, +) / Double(confidences.count)) * 100) / 100)

    var lines: [String] = [
        "FORT COMPILER DIRECTIVES (PROGRAM-AGNOSTIC):",
        String(format: "Overall parser confidence: %.2f", overallConfidence),
        "Use detected section order and listed exercise anchors as hard conversion constraints for Fort days.",
        "Use the normalized template blocks below as deterministic shape constraints.",
    ]

    for parsed in parsedDays {
        lines.append("\n\(parsed.day.uppercased()) (confidence \(String(format: "%.2f", parsed.confidence)))")
        if !parsed.titleLine.isEmpty {
            lines.append("- Title: \(parsed.titleLine)")
        }

        if parsed.sections.isEmpty {
            lines.append("- No reliable sections detected; fall back to raw text for this day.")
            continue
        }

        for section in parsed.compiledSections {
            let names = section.exercises.map(\.exercise)
            let text = names.isEmpty ? "no anchors extracted" : names.joined(separator: "; ")
            lines.append("- [\(section.blockLetter)-block] \(section.sectionLabel) | header: \(section.rawHeader) | anchors: \(text)")
        }

        lines.append("- Normalized template:")
        lines.append(parsed.compiledTemplate)

        for warning in parsed.warnings {
            lines.append("- Warning: \(warning)")
        }
    }

    let metadata = FortCompilerMetadata(overallConfidence: overallConfidence, days: parsedDays)
    return (lines.joined(separator: "\n"), metadata)
}

public func parsePlanFortEntries(planText: String) -> [String: [PlanFortEntry]] {
    var entriesByDay: [String: [PlanFortEntry]] = [:]
    var currentDay: String?
    var currentEntry: PlanFortEntry?

    for line in planText.components(separatedBy: .newlines) {
        if let dayMatch = planDayRegex.firstMatch(in: line, options: [], range: fullRange(of: line)),
           let dayRange = Range(dayMatch.range(at: 1), in: line),
           let dayName = extractDayName(String(line[dayRange])) {
            currentDay = dayName
            currentEntry = nil
            entriesByDay[dayName, default: []] = entriesByDay[dayName, default: []]
            continue
        }

        if let exerciseMatch = planExerciseRegex.firstMatch(in: line, options: [], range: fullRange(of: line)),
           let blockRange = Range(exerciseMatch.range(at: 1), in: line),
           let exerciseRange = Range(exerciseMatch.range(at: 2), in: line),
           let currentDay {
            let block = String(line[blockRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let exercise = String(line[exerciseRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let entry = PlanFortEntry(
                day: currentDay,
                block: block,
                blockRank: blockRank(block),
                exercise: exercise,
                load: nil,
                reps: nil,
                notes: ""
            )
            entriesByDay[currentDay, default: []].append(entry)
            currentEntry = entry
            continue
        }

        guard let current = currentEntry,
              var dayEntries = entriesByDay[current.day]
        else {
            continue
        }

        let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if let parsedPrescription = parsePrescriptionLine(stripped) {
            if let index = dayEntries.lastIndex(where: { $0.block == current.block && $0.exercise == current.exercise }) {
                let updated = PlanFortEntry(
                    day: current.day,
                    block: current.block,
                    blockRank: current.blockRank,
                    exercise: current.exercise,
                    load: parsedPrescription.load,
                    reps: parsedPrescription.reps,
                    notes: current.notes
                )
                dayEntries[index] = updated
                entriesByDay[current.day] = dayEntries
                currentEntry = updated
            }
            continue
        }

        if stripped.lowercased().hasPrefix("- **notes:**") {
            if let index = dayEntries.lastIndex(where: { $0.block == current.block && $0.exercise == current.exercise }) {
                let updated = PlanFortEntry(day: current.day, block: current.block, blockRank: current.blockRank, exercise: current.exercise, load: current.load, reps: current.reps, notes: stripped)
                dayEntries[index] = updated
                entriesByDay[current.day] = dayEntries
                currentEntry = updated
            }
        }
    }

    return entriesByDay
}

private func canonicalAliasName(_ value: String) -> String {
    var normalized = normalizeExerciseName(value)
    if normalized.isEmpty {
        return ""
    }
    normalized = normalized.replacingOccurrences(of: "\\b(dumbbell|db)\\b", with: " ", options: .regularExpression)
    normalized = fcCollapseWhitespace(normalized).trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized
}

private func aliasKeys(_ value: String) -> Set<String> {
    let normalized = normalizeExerciseName(value)
    if normalized.isEmpty {
        return []
    }
    var keys: Set<String> = [normalized]
    let canonical = canonicalAliasName(normalized)
    if !canonical.isEmpty {
        keys.insert(canonical)
    }
    return keys
}

private func buildAliasMap(_ exerciseAliases: [String: String]) -> [String: Set<String>] {
    var aliasMap: [String: Set<String>] = [:]
    if exerciseAliases.isEmpty {
        return aliasMap
    }

    for (source, target) in exerciseAliases {
        let sourceKeys = aliasKeys(source)
        let targetKeys = aliasKeys(target)
        if sourceKeys.isEmpty || targetKeys.isEmpty {
            continue
        }

        for sourceNorm in sourceKeys {
            for targetNorm in targetKeys {
                aliasMap[sourceNorm, default: []].insert(targetNorm)
                aliasMap[targetNorm, default: []].insert(sourceNorm)
            }
        }
    }

    return aliasMap
}

private func matchesExpectedExercise(expectedName: String, actualName: String, aliasMap: [String: Set<String>]) -> Bool {
    let normalizer = getNormalizer()

    if normalizer.areSameExercise(expectedName, actualName) {
        return true
    }

    let expectedKeys = aliasKeys(expectedName)
    let actualKeys = aliasKeys(actualName)
    if expectedKeys.isEmpty || actualKeys.isEmpty {
        return false
    }

    var candidates = expectedKeys
    for expectedKey in expectedKeys {
        candidates.formUnion(aliasMap[expectedKey, default: []])
        for (aliasSource, targets) in aliasMap where !aliasSource.isEmpty && expectedKey.contains(aliasSource) {
            candidates.formUnion(targets)
        }
    }

    for candidate in candidates {
        for actualKey in actualKeys where candidate == actualKey || candidate.contains(actualKey) || actualKey.contains(candidate) {
            return true
        }
    }
    return false
}

public func validateFortFidelity(planText: String, metadata: FortCompilerMetadata?, exerciseAliases: [String: String] = [:]) -> FortFidelityResult {
    guard let metadata else {
        return FortFidelityResult(
            violations: [],
            summary: "Fort fidelity: no compiler metadata provided.",
            expectedAnchors: 0,
            matchedAnchors: 0
        )
    }

    if metadata.days.isEmpty {
        return FortFidelityResult(
            violations: [],
            summary: "Fort fidelity: no parsed Fort days to validate.",
            expectedAnchors: 0,
            matchedAnchors: 0
        )
    }

    let aliasMap = buildAliasMap(exerciseAliases)
    let entriesByDay = parsePlanFortEntries(planText: planText)

    var violations: [FortFidelityViolation] = []
    var expectedAnchors = 0
    var matchedAnchors = 0

    for daySpec in metadata.days {
        let dayName = daySpec.day.uppercased()
        let compiledSections = daySpec.compiledSections
        if compiledSections.isEmpty {
            continue
        }

        let actualEntries = entriesByDay[dayName] ?? []
        if actualEntries.isEmpty {
            violations.append(
                FortFidelityViolation(
                    code: "fort_day_missing",
                    message: "\(dayName) is missing from generated plan.",
                    day: dayName
                )
            )
            expectedAnchors += compiledSections.reduce(0) { $0 + $1.exercises.count }
            continue
        }

        var usedIndices: Set<Int> = []
        var sectionRanks: [(sectionLabel: String, rank: Int)] = []

        for section in compiledSections {
            var sectionMatches: [PlanFortEntry] = []

            for expectedEntry in section.exercises {
                expectedAnchors += 1
                var matchedIndex: Int?

                for (index, actualEntry) in actualEntries.enumerated() {
                    if usedIndices.contains(index) {
                        continue
                    }
                    if matchesExpectedExercise(expectedName: expectedEntry.exercise, actualName: actualEntry.exercise, aliasMap: aliasMap) {
                        matchedIndex = index
                        break
                    }
                }

                guard let matchedIndex else {
                    violations.append(
                        FortFidelityViolation(
                            code: "fort_missing_anchor",
                            message: "Missing Fort anchor exercise '\(expectedEntry.exercise)' from section '\(section.sectionLabel)' on \(dayName).",
                            day: dayName,
                            exercise: expectedEntry.exercise
                        )
                    )
                    continue
                }

                usedIndices.insert(matchedIndex)
                let matchedEntry = actualEntries[matchedIndex]
                matchedAnchors += 1
                sectionMatches.append(matchedEntry)

                if ["strength_build", "strength_work", "strength_backoff"].contains(section.sectionID),
                   isMainLiftName(expectedEntry.exercise),
                   (matchedEntry.load ?? 0) <= 0 {
                    violations.append(
                        FortFidelityViolation(
                            code: "fort_missing_load",
                            message: "Expected explicit load for main Fort lift '\(matchedEntry.exercise)' on \(dayName).",
                            day: dayName,
                            exercise: matchedEntry.exercise
                        )
                    )
                }

                if matchedEntry.notes.lowercased().contains("added by deterministic fort anchor repair") {
                    violations.append(
                        FortFidelityViolation(
                            code: "fort_placeholder_prescription",
                            message: "Fort anchor '\(matchedEntry.exercise)' on \(dayName) still has deterministic placeholder notes.",
                            day: dayName,
                            exercise: matchedEntry.exercise
                        )
                    )
                }
            }

            let ranks = sectionMatches.compactMap(\.blockRank)
            if let minRank = ranks.min() {
                sectionRanks.append((section.sectionLabel, minRank))
            }
        }

        var previous: (sectionLabel: String, rank: Int)?
        for sectionRank in sectionRanks {
            if let previous, sectionRank.rank < previous.rank {
                violations.append(
                    FortFidelityViolation(
                        code: "fort_section_order",
                        message: "Fort section order drift on \(dayName): '\(sectionRank.sectionLabel)' appears before '\(previous.sectionLabel)'.",
                        day: dayName
                    )
                )
            }
            previous = sectionRank
        }
    }

    let summary: String
    if expectedAnchors > 0 {
        summary = "Fort fidelity: \(matchedAnchors)/\(expectedAnchors) anchors matched, \(violations.count) violation(s)."
    } else {
        summary = "Fort fidelity: no anchors available to validate."
    }

    return FortFidelityResult(
        violations: violations,
        summary: summary,
        expectedAnchors: expectedAnchors,
        matchedAnchors: matchedAnchors
    )
}

private func parsePlanDaySegments(planText: String) -> ([String], [DaySegment]) {
    let lines = planText.components(separatedBy: .newlines)
    var prefixLines: [String] = []
    var segments: [DaySegment] = []
    var currentDay: String?
    var currentLines: [String] = []

    for line in lines {
        if let match = planDayRegex.firstMatch(in: line, options: [], range: fullRange(of: line)),
           let dayRange = Range(match.range(at: 1), in: line),
           let dayName = extractDayName(String(line[dayRange])) {
            if let currentDay {
                segments.append(DaySegment(day: currentDay, lines: currentLines))
            }
            currentDay = dayName
            currentLines = [line]
            continue
        }

        if currentDay == nil {
            prefixLines.append(line)
        } else {
            currentLines.append(line)
        }
    }

    if let currentDay {
        segments.append(DaySegment(day: currentDay, lines: currentLines))
    }

    return (prefixLines, segments)
}

private func parseDayEntriesWithSpans(dayLines: [String]) -> [DayEntrySpan] {
    var entries: [DayEntrySpan] = []

    for (index, line) in dayLines.enumerated() {
        guard let match = planExerciseRegex.firstMatch(in: line, options: [], range: fullRange(of: line)),
              let blockRange = Range(match.range(at: 1), in: line),
              let exerciseRange = Range(match.range(at: 2), in: line)
        else {
            continue
        }

        let block = String(line[blockRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let exercise = String(line[exerciseRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let blockMatch = makeRegex("^([A-Z])(\\d+)$", options: [.caseInsensitive]).firstMatch(in: block, options: [], range: fullRange(of: block))

        let blockLetter: String
        let blockIndex: Int
        if let blockMatch,
           let letterRange = Range(blockMatch.range(at: 1), in: block),
           let indexRange = Range(blockMatch.range(at: 2), in: block) {
            blockLetter = String(block[letterRange]).uppercased()
            blockIndex = Int(block[indexRange]) ?? 0
        } else {
            blockLetter = ""
            blockIndex = 0
        }

        entries.append(
            DayEntrySpan(
                startIndex: index,
                endIndex: dayLines.count,
                block: block,
                blockLetter: blockLetter,
                blockIndex: blockIndex,
                blockRank: blockRank(block),
                exercise: exercise
            )
        )
    }

    for index in 0..<entries.count {
        let nextStart = (index + 1 < entries.count) ? entries[index + 1].startIndex : dayLines.count
        let current = entries[index]
        entries[index] = DayEntrySpan(
            startIndex: current.startIndex,
            endIndex: nextStart,
            block: current.block,
            blockLetter: current.blockLetter,
            blockIndex: current.blockIndex,
            blockRank: current.blockRank,
            exercise: current.exercise
        )
    }

    return entries
}

private func repairDefaultPrescription(sectionID: String, exerciseName: String) -> (String, String, String, String) {
    let isMain = isMainLiftName(exerciseName)
    let norm = normalizeExerciseName(exerciseName)
    let isDB = " \(norm) ".contains(" db ") || norm.contains("dumbbell")

    if ["prep_mobility", "conditioning"].contains(sectionID) {
        return ("1", "60", "0", "None")
    }
    if isMain {
        return ("1", "1", "20", "180 seconds")
    }
    if isDB {
        return ("3", "10", "10", "90 seconds")
    }
    return ("3", "10", "0", "90 seconds")
}

private func defaultBlockLines(blockLabel: String, exerciseName: String, sectionID: String) -> [String] {
    let (sets, reps, load, rest) = repairDefaultPrescription(sectionID: sectionID, exerciseName: exerciseName)
    return [
        "### \(blockLabel). \(exerciseName)",
        "- \(sets) x \(reps) @ \(load) kg",
        "- **Rest:** \(rest)",
        "- **Notes:** Added by deterministic Fort anchor repair. Replace prescription with exact Fort values if needed.",
    ]
}

private func normalizeBlockLines(blockLabel: String, exerciseName: String, sourceLines: [String], sectionID: String) -> ([String], Bool) {
    let defaultLines = defaultBlockLines(blockLabel: blockLabel, exerciseName: exerciseName, sectionID: sectionID)
    if sourceLines.isEmpty {
        return (defaultLines, true)
    }

    var prescriptionLine: String?
    var restLine: String?
    var notesLine: String?

    for raw in sourceLines.dropFirst() {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty {
            continue
        }
        if prescriptionLine == nil, planPrescriptionRegex.firstMatch(in: line, options: [], range: fullRange(of: line)) != nil {
            prescriptionLine = line
            continue
        }
        if restLine == nil, line.lowercased().hasPrefix("- **rest:**") {
            restLine = line
            continue
        }
        if notesLine == nil, line.lowercased().hasPrefix("- **notes:**") {
            notesLine = line
            continue
        }
    }

    var missing = false
    if prescriptionLine == nil {
        prescriptionLine = defaultLines[1]
        missing = true
    }
    if restLine == nil {
        restLine = defaultLines[2]
        missing = true
    }
    if notesLine == nil {
        notesLine = defaultLines[3]
        missing = true
    }

    let normalized = [
        "### \(blockLabel). \(exerciseName)",
        prescriptionLine ?? defaultLines[1],
        restLine ?? defaultLines[2],
        notesLine ?? defaultLines[3],
    ]
    return (normalized, missing)
}

private func joinPlanSegments(prefixLines: [String], segments: [DaySegment]) -> String {
    var lines = prefixLines
    for segment in segments {
        if let last = lines.last, !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
        }
        lines.append(contentsOf: segment.lines)
    }

    var output = lines.joined(separator: "\n")
    while output.hasSuffix("\n\n") {
        output = String(output.dropLast())
    }
    if !output.hasSuffix("\n") {
        output += "\n"
    }
    return output
}

public func repairPlanFortAnchors(planText: String, metadata: FortCompilerMetadata?, exerciseAliases: [String: String] = [:]) -> (String, FortRepairSummary) {
    if planText.isEmpty {
        let summary = FortRepairSummary(inserted: 0, insertions: [], dropped: 0, rebuiltDays: 0, summary: "Fort anchor repair skipped: empty plan.")
        return (planText, summary)
    }

    guard let metadata else {
        let summary = FortRepairSummary(inserted: 0, insertions: [], dropped: 0, rebuiltDays: 0, summary: "Fort anchor repair skipped: no metadata.")
        return (planText, summary)
    }

    if metadata.days.isEmpty {
        let summary = FortRepairSummary(inserted: 0, insertions: [], dropped: 0, rebuiltDays: 0, summary: "Fort anchor repair skipped: no metadata.")
        return (planText, summary)
    }

    let aliasMap = buildAliasMap(exerciseAliases)
    let (prefixLines, existingSegments) = parsePlanDaySegments(planText: planText)
    var segments = existingSegments
    var segmentsByDay: [String: Int] = [:]
    for (index, segment) in segments.enumerated() {
        segmentsByDay[segment.day] = index
    }

    var insertions: [FortRepairInsertion] = []
    var droppedEntries = 0
    var rebuiltDays = 0
    var addedDay = false

    for daySpec in metadata.days {
        let dayName = daySpec.day.uppercased()
        let compiledSections = daySpec.compiledSections
        if compiledSections.isEmpty {
            continue
        }

        let segmentIndex: Int
        if let existing = segmentsByDay[dayName] {
            segmentIndex = existing
        } else {
            segments.append(DaySegment(day: dayName, lines: ["## \(dayName)"]))
            segmentIndex = segments.count - 1
            segmentsByDay[dayName] = segmentIndex
            addedDay = true
        }

        var segment = segments[segmentIndex]
        let dayLines = segment.lines
        let entries = parseDayEntriesWithSpans(dayLines: dayLines)

        var blockEntries = entries.map { span in
            WorkingDayEntry(
                span: span,
                lines: Array(dayLines[span.startIndex..<span.endIndex]),
                used: false
            )
        }

        let header = (segment.lines.first != nil && planDayRegex.firstMatch(in: segment.lines.first ?? "", options: [], range: fullRange(of: segment.lines.first ?? "")) != nil)
            ? (segment.lines.first ?? "## \(dayName)")
            : "## \(dayName)"

        var rebuiltLines = [header]

        for section in compiledSections {
            for expected in section.exercises {
                let expectedName = expected.exercise
                let expectedBlock = expected.block
                if expectedName.isEmpty {
                    continue
                }

                var matchIndex: Int?
                for index in blockEntries.indices {
                    if blockEntries[index].used {
                        continue
                    }
                    if matchesExpectedExercise(expectedName: expectedName, actualName: blockEntries[index].span.exercise, aliasMap: aliasMap) {
                        matchIndex = index
                        break
                    }
                }

                let normalizedLines: [String]
                if let matchIndex {
                    blockEntries[matchIndex].used = true
                    let result = normalizeBlockLines(
                        blockLabel: expectedBlock,
                        exerciseName: expectedName,
                        sourceLines: blockEntries[matchIndex].lines,
                        sectionID: section.sectionID
                    )
                    normalizedLines = result.0
                    if result.1 {
                        insertions.append(
                            FortRepairInsertion(day: dayName, sectionID: section.sectionID, exercise: expectedName, block: expectedBlock)
                        )
                    }
                } else {
                    normalizedLines = defaultBlockLines(blockLabel: expectedBlock, exerciseName: expectedName, sectionID: section.sectionID)
                    insertions.append(
                        FortRepairInsertion(day: dayName, sectionID: section.sectionID, exercise: expectedName, block: expectedBlock)
                    )
                }

                if rebuiltLines.count > 1 {
                    rebuiltLines.append("")
                }
                rebuiltLines.append(contentsOf: normalizedLines)
            }
        }

        droppedEntries += blockEntries.filter { !$0.used }.count
        segment.lines = rebuiltLines
        segments[segmentIndex] = segment
        rebuiltDays += 1
    }

    if rebuiltDays == 0 {
        let summary = FortRepairSummary(
            inserted: 0,
            insertions: [],
            dropped: 0,
            rebuiltDays: 0,
            summary: "Fort anchor repair skipped: no Fort days rebuilt."
        )
        return (planText, summary)
    }

    if addedDay {
        segments.sort { weekdayRank($0.day) < weekdayRank($1.day) }
    }

    let patched = joinPlanSegments(prefixLines: prefixLines, segments: segments)
    let summaryText = "Fort anchor repair: rebuilt \(rebuiltDays) Fort day(s), inserted \(insertions.count) missing/filled anchor(s), dropped \(droppedEntries) non-anchor entry block(s)."
    let summary = FortRepairSummary(
        inserted: insertions.count,
        insertions: insertions,
        dropped: droppedEntries,
        rebuiltDays: rebuiltDays,
        summary: summaryText
    )
    return (patched, summary)
}
