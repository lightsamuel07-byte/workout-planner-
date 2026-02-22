import Foundation

func makeRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
    do {
        return try NSRegularExpression(pattern: pattern, options: options)
    } catch {
        fatalError("Invalid regex: \(pattern)")
    }
}

func fullRange(of string: String) -> NSRange {
    NSRange(string.startIndex..<string.endIndex, in: string)
}

private func replacingMatches(in input: String, regex: NSRegularExpression, with template: String) -> String {
    regex.stringByReplacingMatches(in: input, options: [], range: fullRange(of: input), withTemplate: template)
}

private func collapseWhitespace(_ value: String) -> String {
    value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

private let stripParenPatterns: [NSRegularExpression] = [
    makeRegex("\\s*\\(warm-?up(?:\\s+set)?\\s*\\d*\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(cluster\\s+(?:singles|doubles)\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(build\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(working\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(back-?off\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(emom\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(max\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(last\\s+set\\s*=\\s*myo-?rep\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(myo-?rep\\s+finisher\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(std\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(standard\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(no\\s+belt\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(finisher\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(flush\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(treadmill\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(opt\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(second\\s+set\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(db\\s+optional\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(all-?out\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(at\\s+pace\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(hold\\s+target\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(max\\s+power\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(rhythm\\s+test\\)", options: [.caseInsensitive]),
    makeRegex("\\s*\\(sequence\\)", options: [.caseInsensitive]),
]

private let stripDashSuffix = makeRegex(
    "\\s*[—–-]+\\s*(?:breakpoint|calibration|calib|work)\\s*$",
    options: [.caseInsensitive]
)

private let abbreviationMap: [(NSRegularExpression, String)] = [
    (makeRegex("\\bez[\\s-]*bar\\b", options: [.caseInsensitive]), "EZ-Bar"),
    (makeRegex("\\bbike\\s*erg\\b", options: [.caseInsensitive]), "BikeErg"),
    (makeRegex("\\bski\\s*erg\\b", options: [.caseInsensitive]), "SkiErg"),
    (makeRegex("\\brow\\s*erg\\b", options: [.caseInsensitive]), "RowErg"),
]

private let depluralizePatterns: [(NSRegularExpression, String)] = [
    (makeRegex("\\bwindmills\\b", options: [.caseInsensitive]), "Windmill"),
    (makeRegex("\\bburpees\\b", options: [.caseInsensitive]), "Burpee"),
    (makeRegex("\\bplanks\\b", options: [.caseInsensitive]), "Plank"),
    (makeRegex("\\bpull-ups\\b", options: [.caseInsensitive]), "Pull-Up"),
    (makeRegex("\\bpush-ups\\b", options: [.caseInsensitive]), "Push-Up"),
    (makeRegex("\\bface pulls\\b", options: [.caseInsensitive]), "Face Pull"),
]

private let aliasGroups: [[String]] = [
    ["Goblet Squat", "Goblet Squat (Std)", "Goblet Squat (standard)"],
    ["DB RDL (Glute Optimized)", "DB RDL (glute-opt.)"],
    ["Heel-Elevated DB Goblet Squat", "Heels-Elevated DB Goblet Squat"],
    ["Side-Lying Windmill", "Side-Lying Windmills"],
    ["Poliquin Step-Up", "Poliquin step up", "Poliquin Step-Up (DB optional)"],
    ["Face Pull (Rope)", "Face Pull (rope)", "Face Pull (Rope, High-to-Forehead)", "Cable Face Pull (rope)", "Cable Face Pull (Rear Delt Emphasis)", "Face Pulls", "Face Pull"],
    ["Standing Calf Raise", "Standing Calf Raise (Machine)", "Standing Calf Raise (Smith Machine or DB)", "Standing/Seated Calf Raise"],
    ["Bench Press", "Bench"],
    ["McGill Big-3", "McGill Big 3 (sequence)", "McGill Big-3 micro"],
    ["Incline Walk", "Incline Walk (Finisher)", "Incline Walk (Warm-up)", "Incline Walk (flush)", "Incline Walk (treadmill)"],
    ["DB Hammer Curl", "DB Hammer Curl (neutral)", "Hammer Curl (Neutral Grip)"],
    ["Straight-Arm Cable Pulldown", "Straight-Arm Pulldown"],
    ["Rope Pressdown", "Tricep Pushdown (Rope Attachment)"],
    ["Overhead Cable Tricep Extension (Rope)", "Overhead Rope Tricep Extension"],
    ["Reverse Pec Deck", "Reverse Pec Deck (rear-delt)"],
    ["Rear-Delt Cable/Machine", "Rear-Delt Machine/Cable"],
    ["Cable Curl (Straight Bar, Pronated Grip)", "Cable Curl (Straight Bar, Overhand/Pronated)"],
    ["Seated DB Shoulder Press", "Seated DB Press"],
    ["Chest-Supported DB Row", "Chest-Supported DB Row (30\u{00B0})", "Chest-Supported Row (30)", "Chest-Supported DB Row (max)"],
    ["Kneeling Cable Crunch", "Cable Crunch"],
    ["Dry Sauna", "Dry Sauna (opt)"],
    ["Hamstring Bridge Walkouts", "Hamstring Walkout"],
    ["DB Sumo Squat", "DB Sumo Squat (LAST SET = MYO-REP)", "DB Sumo Squat (MYO-REP FINISHER)"],
    ["Standing EZ-Bar Curl", "Standing EZ Bar Bicep Curl (LAST SET = MYO-REP)", "Standing EZ Bar Bicep Curl (MYO-REP FINISHER)"],
    ["EZ Bar Rear Delt Row", "EZ Bar Rear Delt Row (MYO-REP FINISHER)"],
    ["Seated Leg Curl (machine)", "Seated Leg Curl (roller swap)"],
    ["Barbell Curl", "Barbell Curl (max)", "Standing Barbell Curl (supinated)"],
    ["EZ-Bar Curl", "EZ-Bar Curl (max)", "EZ-Bar Curl (reverse grip)"],
    ["Pull-Up", "Pull-Ups", "Pull-Ups (max)"],
    ["Push-Up", "Push-Ups", "Push-Ups (max)"],
    ["Plyo Push-Up", "Plyo Push-Up (EMOM)"],
    ["BikeErg", "BikeErg (all-out)", "BikeErg (at pace)", "BikeErg (hold target)", "BikeErg (max power)"],
    ["SkiErg", "SkiErg (at pace)", "SkiErg (hold target)"],
    ["Rower", "Rower (all-out)", "Rower (hold target)", "RowErg Sprints"],
    ["90/90 Hip Switch", "90/90 Hip Switch (Second Set)"],
    ["Adductor Rockback", "Adductor Rockback (Second Set)"],
    ["Ab Rollout", "Ab Rollout (wheel/cable bar)"],
    ["15\u{00B0} EZ-Bar Triceps Extension", "15\u{00B0} EZ Bar Tricep Extension", "15\u{00B0} EZ-Bar Triceps Ext (max)", "15\u{00B0} ez Triceps Extension"],
    ["Straight-Bar Triceps Extension (15\u{00B0})", "Straight-Bar Triceps Ext (max)"],
]

private let bodyPartCategories: [(String, String)] = [
    ("curl", "biceps"),
    ("bicep", "biceps"),
    ("press", "push"),
    ("bench", "push"),
    ("fly", "push"),
    ("squat", "legs_quad"),
    ("leg extension", "legs_quad"),
    ("deadlift", "legs_pull"),
    ("rdl", "legs_pull"),
    ("row", "back"),
    ("pulldown", "back"),
    ("pull-up", "back"),
    ("lateral raise", "delts"),
    ("shoulder", "delts"),
    ("calf", "calves"),
    ("tricep", "triceps"),
    ("pushdown", "triceps"),
    ("skullcrusher", "triceps"),
]

public final class ExerciseNormalizer: @unchecked Sendable {
    private var aliasToCanonical: [String: String]
    private var canonicalKeyToDisplay: [String: String]

    public init(swapsFile: String? = "exercise_swaps.yaml") {
        self.aliasToCanonical = [:]
        self.canonicalKeyToDisplay = [:]

        for group in aliasGroups where !group.isEmpty {
            let canonicalDisplay = group[0]
            let canonicalKey = computeCanonicalKey(canonicalDisplay)
            canonicalKeyToDisplay[canonicalKey] = canonicalDisplay

            for alias in group {
                let aliasKey = computeCanonicalKey(alias)
                aliasToCanonical[aliasKey] = canonicalKey

                let rawLower = collapseWhitespace(alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                aliasToCanonical[rawLower] = canonicalKey
            }
        }

        loadSwapAliases(swapsFile: swapsFile)
    }

    public func canonicalKey(_ name: String?) -> String {
        guard let name, !name.isEmpty else {
            return ""
        }

        let key = computeCanonicalKey(name)
        if let alias = aliasToCanonical[key] {
            return alias
        }

        let (base, qualifier) = splitBaseQualifier(key)
        if !qualifier.isEmpty, let canonicalBase = aliasToCanonical[base] {
            return "\(canonicalBase) \(qualifier)"
        }

        return key
    }

    public func canonicalName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else {
            return ""
        }

        let key = canonicalKey(raw)
        if let display = canonicalKeyToDisplay[key] {
            return display
        }

        var cleaned = collapseWhitespace(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        for pattern in stripParenPatterns {
            cleaned = replacingMatches(in: cleaned, regex: pattern, with: "")
        }
        cleaned = replacingMatches(in: cleaned, regex: stripDashSuffix, with: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func areSameExercise(_ a: String?, _ b: String?) -> Bool {
        guard let a, !a.isEmpty, let b, !b.isEmpty else {
            return false
        }

        let keyA = canonicalKey(a)
        let keyB = canonicalKey(b)

        if keyA == keyB {
            return true
        }

        if substringMatch(keyA, keyB) {
            return true
        }

        return fuzzyMatch(keyA, keyB)
    }

    public func findMatch(_ raw: String?, candidates: [String]) -> String? {
        guard let raw, !raw.isEmpty, !candidates.isEmpty else {
            return nil
        }

        let key = canonicalKey(raw)

        for candidate in candidates {
            if canonicalKey(candidate) == key {
                return candidate
            }
        }

        for candidate in candidates where areSameExercise(raw, candidate) {
            return candidate
        }

        return nil
    }

    public func registerAlias(rawName: String, canonicalDisplay: String) {
        let canonicalKey = computeCanonicalKey(canonicalDisplay)
        let rawKey = computeCanonicalKey(rawName)
        aliasToCanonical[rawKey] = canonicalKey

        if canonicalKeyToDisplay[canonicalKey] == nil {
            canonicalKeyToDisplay[canonicalKey] = canonicalDisplay
        }
    }

    public func isDBExercise(_ name: String?) -> Bool {
        let key = computeCanonicalKey(name)
        return " \(key) ".contains(" db ") || key.contains("dumbbell")
    }

    public func isMainPlateLift(_ name: String?) -> Bool {
        let key = computeCanonicalKey(name)
        if isDBExercise(name) {
            return false
        }

        return ["back squat", "front squat", "deadlift", "bench press", "chest press"].contains {
            key.contains($0)
        }
    }

    private func computeCanonicalKey(_ name: String?) -> String {
        guard let name else {
            return ""
        }

        var result = collapseWhitespace(name.trimmingCharacters(in: .whitespacesAndNewlines))
        if result.isEmpty {
            return ""
        }

        for pattern in stripParenPatterns {
            result = replacingMatches(in: result, regex: pattern, with: "")
        }

        result = replacingMatches(in: result, regex: stripDashSuffix, with: "")

        for (pattern, replacement) in abbreviationMap {
            result = replacingMatches(in: result, regex: pattern, with: replacement)
        }

        for (pattern, replacement) in depluralizePatterns {
            result = replacingMatches(in: result, regex: pattern, with: replacement)
        }

        result = collapseWhitespace(result).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        result = result.replacingOccurrences(of: "glute-opt.", with: "glute optimized")

        return result
    }

    private func splitBaseQualifier(_ key: String) -> (String, String) {
        let regex = makeRegex("^(.+?)\\s*(\\([^)]+\\).*)$")
        guard
            let match = regex.firstMatch(in: key, options: [], range: fullRange(of: key)),
            let baseRange = Range(match.range(at: 1), in: key),
            let qualifierRange = Range(match.range(at: 2), in: key)
        else {
            return (key, "")
        }

        return (
            key[baseRange].trimmingCharacters(in: .whitespacesAndNewlines),
            key[qualifierRange].trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func tokenize(_ key: String) -> Set<String> {
        let stopWords: Set<String> = ["", "the", "a", "an", "of", "for", "with"]
        let parts = key
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0) }
            .filter { !stopWords.contains($0) }
        return Set(parts)
    }

    private func bodyPartCategory(_ key: String) -> String? {
        for (token, category) in bodyPartCategories where key.contains(token) {
            return category
        }
        return nil
    }

    private func substringMatch(_ keyA: String, _ keyB: String) -> Bool {
        guard !keyA.isEmpty, !keyB.isEmpty else {
            return false
        }

        if !keyA.contains(keyB) && !keyB.contains(keyA) {
            return false
        }

        let catA = bodyPartCategory(keyA)
        let catB = bodyPartCategory(keyB)
        if let catA, let catB, catA != catB {
            return false
        }

        let tokensA = tokenize(keyA)
        let tokensB = tokenize(keyB)
        if tokensA.isEmpty || tokensB.isEmpty {
            return false
        }

        let overlap = tokensA.intersection(tokensB).count
        let smaller = min(tokensA.count, tokensB.count)
        guard smaller > 0 else {
            return false
        }

        return Double(overlap) / Double(smaller) >= 0.6
    }

    private func fuzzyMatch(_ keyA: String, _ keyB: String) -> Bool {
        let tokensA = tokenize(keyA)
        let tokensB = tokenize(keyB)
        if tokensA.isEmpty || tokensB.isEmpty {
            return false
        }

        let catA = bodyPartCategory(keyA)
        let catB = bodyPartCategory(keyB)
        if let catA, let catB, catA != catB {
            return false
        }

        let intersection = tokensA.intersection(tokensB).count
        let union = tokensA.union(tokensB).count
        guard union > 0 else {
            return false
        }

        let jaccard = Double(intersection) / Double(union)
        return jaccard >= 0.7
    }

    private func loadSwapAliases(swapsFile: String?) {
        guard let swapsFile, !swapsFile.isEmpty else {
            return
        }

        guard FileManager.default.fileExists(atPath: swapsFile) else {
            return
        }

        guard let content = try? String(contentsOfFile: swapsFile, encoding: .utf8) else {
            return
        }

        for (original, replacement) in parseExerciseSwaps(from: content) {
            let originalKey = computeCanonicalKey(original)
            let replacementKey = computeCanonicalKey(replacement)
            if canonicalKeyToDisplay[replacementKey] == nil {
                canonicalKeyToDisplay[replacementKey] = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            aliasToCanonical[originalKey] = replacementKey
        }
    }

    private func parseExerciseSwaps(from yaml: String) -> [(String, String)] {
        var inExerciseSwaps = false
        var pairs: [(String, String)] = []

        for rawLine in yaml.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if !inExerciseSwaps {
                if trimmed == "exercise_swaps:" {
                    inExerciseSwaps = true
                }
                continue
            }

            if !rawLine.hasPrefix("  ") {
                break
            }

            if trimmed.hasPrefix("#") {
                continue
            }

            var mappingLine = trimmed
            if let commentRange = mappingLine.range(of: " #") {
                mappingLine = String(mappingLine[..<commentRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }

            guard let colonIndex = mappingLine.firstIndex(of: ":") else {
                continue
            }

            let keyPart = String(mappingLine[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let valuePart = String(mappingLine[mappingLine.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            let key = unquote(keyPart)
            let value = unquote(valuePart)

            if !key.isEmpty && !value.isEmpty {
                pairs.append((key, value))
            }
        }

        return pairs
    }

    private func unquote(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }

        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}

private nonisolated(unsafe) var defaultNormalizer: ExerciseNormalizer?

public func getNormalizer(swapsFile: String = "exercise_swaps.yaml") -> ExerciseNormalizer {
    if defaultNormalizer == nil {
        defaultNormalizer = ExerciseNormalizer(swapsFile: swapsFile)
    }
    return defaultNormalizer ?? ExerciseNormalizer(swapsFile: swapsFile)
}

public func resetNormalizer() {
    defaultNormalizer = nil
}
