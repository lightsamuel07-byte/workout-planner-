import Foundation
import WorkoutCore

enum PlanRepairs {
    private static let rangeRegex = try! NSRegularExpression(pattern: "(\\d+)\\s*[-–]\\s*(\\d+)", options: [])

    static func stripPlanPreamble(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") {
                return lines[index...].joined(separator: "\n")
            }
        }
        return text
    }

    static func applyExerciseSwaps(_ planText: String, aliases: [String: String]) -> String {
        if aliases.isEmpty {
            return planText
        }

        let sortedAliases = aliases.keys.sorted { lhs, rhs in
            lhs.count > rhs.count
        }
        var updated = planText

        for raw in sortedAliases {
            guard let replacement = aliases[raw], !replacement.isEmpty else {
                continue
            }
            let pattern = NSRegularExpression.escapedPattern(for: raw)
            let regex = makeLocalRegex(pattern, options: [.caseInsensitive])
            updated = regex.stringByReplacingMatches(
                in: updated,
                options: [],
                range: nsRange(updated),
                withTemplate: replacement
            )
        }

        return updated
    }

    static func enforceEvenDumbbellLoads(_ planText: String) -> String {
        let headerRegex = makeLocalRegex("^\\s*###\\s+[A-Z]\\d+\\.\\s*(.+)$", options: [.caseInsensitive])
        let loadRegex = makeLocalRegex("@\\s*([\\d]+(?:\\.\\d+)?)\\s*kg\\b", options: [.caseInsensitive])

        var currentIsDB = false
        var currentIsMainLift = false
        let normalizer = getNormalizer()
        var lines = planText.components(separatedBy: .newlines)

        for index in lines.indices {
            let line = lines[index]
            if let headerMatch = headerRegex.firstMatch(in: line, options: [], range: nsRange(line)),
               let nameRange = Range(headerMatch.range(at: 1), in: line) {
                let exerciseName = String(line[nameRange])
                currentIsDB = normalizer.isDBExercise(exerciseName)
                currentIsMainLift = normalizer.isMainPlateLift(exerciseName)
                continue
            }

            if !currentIsDB || currentIsMainLift {
                continue
            }

            if line.range(of: "@") == nil || line.lowercased().range(of: "kg") == nil {
                continue
            }

            let replaced = loadRegex.stringByReplacingMatches(
                in: line,
                options: [],
                range: nsRange(line),
                withTemplate: "@ $1 kg"
            )
            let match = loadRegex.firstMatch(in: replaced, options: [], range: nsRange(replaced))
            guard let loadMatch = match,
                  let loadRange = Range(loadMatch.range(at: 1), in: replaced),
                  let raw = Double(replaced[loadRange])
            else {
                continue
            }

            let rounded = Int(round(raw))
            if rounded % 2 == 0 {
                continue
            }

            let lowerEven = rounded - 1
            let upperEven = rounded + 1
            let chosen = abs(raw - Double(lowerEven)) <= abs(raw - Double(upperEven)) ? lowerEven : upperEven
            lines[index] = loadRegex.stringByReplacingMatches(
                in: replaced,
                options: [],
                range: nsRange(replaced),
                withTemplate: "@ \(chosen) kg"
            )
        }

        return lines.joined(separator: "\n")
    }

    static func collapseRangesInPrescriptionLines(_ planText: String) -> (planText: String, collapsedCount: Int) {
        var lines = planText.components(separatedBy: .newlines)
        var collapsedCount = 0

        for index in lines.indices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.hasPrefix("-") || !trimmed.contains(" x ") || !trimmed.contains("@") {
                continue
            }

            guard let match = rangeRegex.firstMatch(in: line, options: [], range: nsRange(line)),
                  let lowRange = Range(match.range(at: 1), in: line),
                  let highRange = Range(match.range(at: 2), in: line),
                  let low = Int(line[lowRange]),
                  let high = Int(line[highRange])
            else {
                continue
            }

            let replacement: String
            let atIndex = line.firstIndex(of: "@")
            if let atIndex, lowRange.lowerBound > atIndex {
                let midpoint = (Double(low) + Double(high)) / 2.0
                replacement = String(format: "%.1f", midpoint).replacingOccurrences(of: "\\.0$", with: "", options: .regularExpression)
            } else {
                replacement = String(high)
            }

            let rangeText = String(line[lowRange.lowerBound..<highRange.upperBound])
            lines[index] = line.replacingOccurrences(of: rangeText, with: replacement, options: [], range: line.range(of: rangeText))
            collapsedCount += 1
        }

        return (lines.joined(separator: "\n"), collapsedCount)
    }

    static func canonicalizeExerciseNames(_ planText: String) -> String {
        let headerRegex = makeLocalRegex("^(\\s*###\\s+[A-Z]\\d+\\.\\s*)(.+)$", options: [.caseInsensitive])
        let normalizer = getNormalizer()
        var lines = planText.components(separatedBy: .newlines)

        for index in lines.indices {
            let line = lines[index]
            guard let match = headerRegex.firstMatch(in: line, options: [], range: nsRange(line)),
                  let prefixRange = Range(match.range(at: 1), in: line),
                  let exerciseRange = Range(match.range(at: 2), in: line)
            else {
                continue
            }

            let prefix = String(line[prefixRange])
            let rawName = String(line[exerciseRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let canonical = normalizer.canonicalName(rawName)
            if canonical != rawName {
                lines[index] = "\(prefix)\(canonical)"
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func makeLocalRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func nsRange(_ value: String) -> NSRange {
        NSRange(value.startIndex..<value.endIndex, in: value)
    }
}
