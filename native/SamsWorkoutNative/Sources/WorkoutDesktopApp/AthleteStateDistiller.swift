import Foundation
import WorkoutCore
import WorkoutPersistence

/// Pre-computed athlete state for a single exercise, distilled from raw DB logs
/// and progression directives. This replaces raw log rows in the generation prompt
/// with actionable signals that the model can use directly for load/rep decisions.
struct ExerciseAthleteState: Equatable, Sendable {
    let exerciseName: String
    let normalizedName: String
    let dayHint: String                // Supplemental day this exercise appears on (e.g. "Tuesday")
    let sessionCount: Int              // Prior sessions with logged data
    let lastPrescription: String       // e.g. "3x12 @24 kg"
    let lastPerformance: String        // Summarized log text from most recent session
    let latestRPE: Double?
    let rpeTrend: String               // "stable ~7", "rising 7->8.5", "falling 8->7", "insufficient data"
    let loadTrend: String              // "stable 24 kg", "rising 22->24 kg", "new exercise"
    let progressionSignal: String      // "LOCK", "PROGRESS", "NEUTRAL"
    let progressionReason: String      // "high RPE", "low RPE", "explicit keep instruction", etc.
    let recommendation: String         // "maintain 3x12 @24 kg", "increase load to 26 kg", etc.
}

/// Telemetry for the distillation step — captures sizing data for token budget analysis.
struct DistillationTelemetry: Equatable, Sendable {
    let exercisesDistilled: Int
    let rawRowsConsumed: Int
    let distilledPromptChars: Int
    let rawContextChars: Int           // What the equivalent raw context would have been
    let compressionRatio: Double       // distilled / raw (lower = more compressed)
}

private struct ProgressionEvaluation {
    let signal: String
    let reason: String
    let recommendation: String
}

enum AthleteStateDistiller {

    // MARK: - Main Entry Point

    /// Distill raw targeted DB rows and progression directives into per-exercise athlete state.
    /// This is a pure local computation — no API calls.
    static func distill(
        targetedRows: [PersistedTargetedLogContextRow],
        progressionDirectives: [ProgressionRuleDirective],
        selectedExercises: [String: [String]]
    ) -> [ExerciseAthleteState] {
        let normalizer = getNormalizer()

        // Group rows by normalized exercise name.
        var rowsByNorm: [String: [PersistedTargetedLogContextRow]] = [:]
        for row in targetedRows {
            rowsByNorm[row.normalizedName, default: []].append(row)
        }

        // Sort each group by date descending (most recent first).
        for key in rowsByNorm.keys {
            rowsByNorm[key]?.sort { $0.sessionDateISO > $1.sessionDateISO }
        }

        // Build a secondary lookup from raw exercise names in DB rows to their normalizedName.
        // This handles cases where the normalizer's canonicalKey output format differs from
        // the pre-stored normalizedName in the DB (e.g., "db hammer curl" vs "db_hammer_curl").
        var normFromRawExercise: [String: String] = [:]
        for row in targetedRows {
            let rawLower = row.exerciseName.lowercased()
            if normFromRawExercise[rawLower] == nil {
                normFromRawExercise[rawLower] = row.normalizedName
            }
        }

        // Helper: look up rows by trying multiple key strategies.
        func lookupRows(for exerciseName: String) -> (key: String, rows: [PersistedTargetedLogContextRow]) {
            let norm = normalizer.canonicalKey(exerciseName)
            if let rows = rowsByNorm[norm], !rows.isEmpty {
                return (norm, rows)
            }
            // Fallback: try the DB's own normalizedName via raw exercise name match.
            if let dbNorm = normFromRawExercise[exerciseName.lowercased()],
               let rows = rowsByNorm[dbNorm], !rows.isEmpty {
                return (dbNorm, rows)
            }
            return (norm, [])
        }

        // Build a lookup from normalized exercise name -> progression directive.
        // Store under both the directive's own normalizedExercise AND the normalizer's key.
        var directivesByNorm: [String: ProgressionRuleDirective] = [:]
        for directive in progressionDirectives {
            let normFromDirective = directive.normalizedExercise.isEmpty
                ? normalizer.canonicalKey(directive.exerciseName)
                : directive.normalizedExercise
            if !normFromDirective.isEmpty {
                directivesByNorm[normFromDirective] = directive
            }
            // Also store under the normalizer's key for the exercise name.
            let normFromNormalizer = normalizer.canonicalKey(directive.exerciseName)
            if !normFromNormalizer.isEmpty {
                directivesByNorm[normFromNormalizer] = directive
            }
        }

        var states: [ExerciseAthleteState] = []
        let dayOrder = ["TUESDAY": 0, "THURSDAY": 1, "SATURDAY": 2]

        // Process exercises in day order, then in selection order within each day.
        for (day, exercises) in selectedExercises.sorted(by: { dayOrder[$0.key.uppercased()] ?? 9 < dayOrder[$1.key.uppercased()] ?? 9 }) {
            for exerciseName in exercises {
                let (norm, rows) = lookupRows(for: exerciseName)
                let displayName = normalizer.canonicalName(exerciseName)
                let directive = directivesByNorm[norm]
                let dayHint = day.capitalized

                let state = distillSingleExercise(
                    exerciseName: displayName,
                    normalizedName: norm,
                    dayHint: dayHint,
                    rows: rows,
                    directive: directive
                )
                states.append(state)
            }
        }

        return states
    }

    static func buildProgressionInsights(
        targetedRows: [PersistedTargetedLogContextRow],
        limit: Int = 8
    ) -> [ProgressionInsight] {
        var rowsByNorm: [String: [PersistedTargetedLogContextRow]] = [:]
        for row in targetedRows {
            rowsByNorm[row.normalizedName, default: []].append(row)
        }

        let groupedRows = rowsByNorm.values
            .map { rows in rows.sorted { $0.sessionDateISO > $1.sessionDateISO } }
            .sorted { lhs, rhs in
                (lhs.first?.sessionDateISO ?? "") > (rhs.first?.sessionDateISO ?? "")
            }

        return groupedRows.prefix(limit).map { rows in
            let latest = rows.first
            let exerciseName = latest?.exerciseName ?? "Unknown Exercise"
            let normalizedName = latest?.normalizedName ?? getNormalizer().canonicalKey(exerciseName)
            let dayHint = latest?.dayLabel.components(separatedBy: " ").first ?? "Recent"
            let state = distillSingleExercise(
                exerciseName: exerciseName,
                normalizedName: normalizedName,
                dayHint: dayHint,
                rows: rows,
                directive: nil
            )

            return ProgressionInsight(
                id: "\(normalizedName)|\(dayHint)",
                exerciseName: state.exerciseName,
                dayHint: state.dayHint,
                sessionCount: state.sessionCount,
                lastPrescription: state.lastPrescription,
                latestRPE: state.latestRPE,
                rpeTrend: state.rpeTrend,
                loadTrend: state.loadTrend,
                progressionSignal: state.progressionSignal,
                progressionReason: state.progressionReason,
                recommendation: state.recommendation
            )
        }
    }

    // MARK: - Single Exercise Distillation

    private static func distillSingleExercise(
        exerciseName: String,
        normalizedName: String,
        dayHint: String,
        rows: [PersistedTargetedLogContextRow],
        directive: ProgressionRuleDirective?
    ) -> ExerciseAthleteState {
        let sessionCount = rows.count

        // Last prescription.
        let lastRx: String
        let lastPerf: String
        if let latest = rows.first {
            lastRx = formatPrescription(sets: latest.sets, reps: latest.reps, load: latest.load)
            lastPerf = summarizeLog(latest.logText)
        } else {
            lastRx = "no prior data"
            lastPerf = "no prior data"
        }

        // RPE analysis.
        let rpes = rows.compactMap { $0.parsedRPE }
        let latestRPE = rpes.first
        let rpeTrend = computeRPETrend(rpes)

        // Load analysis.
        let loads = rows.compactMap { parseLoad($0.load) }
        let loadTrend = computeLoadTrend(loads)

        let progression = evaluateProgression(
            latestRPE: latestRPE,
            sessionCount: sessionCount,
            loads: loads,
            lastRx: lastRx,
            directive: directive,
        )

        return ExerciseAthleteState(
            exerciseName: exerciseName,
            normalizedName: normalizedName,
            dayHint: dayHint,
            sessionCount: sessionCount,
            lastPrescription: lastRx,
            lastPerformance: lastPerf,
            latestRPE: latestRPE,
            rpeTrend: rpeTrend,
            loadTrend: loadTrend,
            progressionSignal: progression.signal,
            progressionReason: progression.reason,
            recommendation: progression.recommendation
        )
    }

    // MARK: - Trend Computation

    static func computeRPETrend(_ rpes: [Double]) -> String {
        guard !rpes.isEmpty else { return "no RPE data" }
        guard rpes.count >= 2 else {
            return "single point: \(formatRPE(rpes[0]))"
        }

        // rpes[0] is most recent, rpes[last] is oldest.
        let recent = rpes[0]
        let older = rpes[min(rpes.count - 1, 3)]
        let delta = recent - older

        if abs(delta) < 0.5 {
            return "stable ~\(formatRPE(recent))"
        } else if delta > 0 {
            return "rising \(formatRPE(older))->\(formatRPE(recent))"
        } else {
            return "falling \(formatRPE(older))->\(formatRPE(recent))"
        }
    }

    static func computeLoadTrend(_ loads: [Double]) -> String {
        guard !loads.isEmpty else { return "no load data" }
        guard loads.count >= 2 else {
            return "single point: \(formatLoadValue(loads[0])) kg"
        }

        let recent = loads[0]
        let older = loads[min(loads.count - 1, 3)]
        let delta = recent - older

        if abs(delta) < 0.5 {
            return "stable \(formatLoadValue(recent)) kg"
        } else if delta > 0 {
            return "rising \(formatLoadValue(older))->\(formatLoadValue(recent)) kg"
        } else {
            return "falling \(formatLoadValue(older))->\(formatLoadValue(recent)) kg"
        }
    }

    // MARK: - Progression Signal

    private static func progressionFromDirective(
        _ directive: ProgressionRuleDirective?
    ) -> (signal: String, reason: String) {
        guard let directive else {
            return ("NEUTRAL", "no prior directive data")
        }

        if directive.holdLock {
            return ("LOCK", directive.reason)
        } else if directive.signal == "progress" {
            return ("PROGRESS", directive.reason)
        } else {
            return ("NEUTRAL", directive.reason)
        }
    }

    private static func progressionSignalFromRecentHistory(
        latestRPE: Double?,
        sessionCount: Int
    ) -> (signal: String, reason: String) {
        guard let latestRPE else {
            return ("NEUTRAL", "no recent RPE data")
        }
        if latestRPE >= 8.5 {
            return ("LOCK", "latest RPE \(formatRPE(latestRPE)) suggests near limit")
        }
        if latestRPE <= 7.0, sessionCount >= 2 {
            return ("PROGRESS", "latest RPE \(formatRPE(latestRPE)) with repeated exposure")
        }
        return ("NEUTRAL", "latest RPE \(formatRPE(latestRPE)) suggests maintain")
    }

    // MARK: - Recommendation Engine

    private static func evaluateProgression(
        latestRPE: Double?,
        sessionCount: Int,
        loads: [Double],
        lastRx: String,
        directive: ProgressionRuleDirective?
    ) -> ProgressionEvaluation {
        let historySignal = progressionSignalFromRecentHistory(
            latestRPE: latestRPE,
            sessionCount: sessionCount
        )
        let directiveSignal = progressionFromDirective(directive)
        let chosenSignal: (signal: String, reason: String)

        if let directive, directive.holdLock || directive.signal == "progress" {
            chosenSignal = directiveSignal
        } else {
            chosenSignal = historySignal
        }

        let recommendation = generateRecommendation(
            signal: chosenSignal.signal,
            latestRPE: latestRPE,
            loads: loads,
            lastRx: lastRx,
            directive: directive,
            sessionCount: sessionCount
        )

        return ProgressionEvaluation(
            signal: chosenSignal.signal,
            reason: chosenSignal.reason,
            recommendation: recommendation
        )
    }

    private static func generateRecommendation(
        signal: String,
        latestRPE: Double?,
        loads: [Double],
        lastRx: String,
        directive: ProgressionRuleDirective?,
        sessionCount: Int
    ) -> String {
        if sessionCount == 0 {
            return "new exercise — infer starting load from strength profile and target RPE 7-8"
        }

        switch signal {
        case "LOCK":
            if let directive, let reps = directive.targetReps, let load = directive.targetLoad {
                return "maintain \(reps) reps @ \(formatLoadValue(load)) kg (locked)"
            }
            return "maintain current prescription (locked)"

        case "PROGRESS":
            if let latestRPE {
                if latestRPE <= 7.0, let lastLoad = loads.first {
                    // Low RPE — suggest load increase.
                    let suggestedLoad = nextEvenDBLoad(lastLoad)
                    return "increase load to \(formatLoadValue(suggestedLoad)) kg (RPE \(formatRPE(latestRPE)) allows progression)"
                } else if latestRPE <= 7.5 {
                    return "add 1-2 reps OR small load increase (RPE \(formatRPE(latestRPE)))"
                }
            }
            return "single-variable progression allowed (load OR reps, not both)"

        default:
            if let latestRPE, latestRPE >= 8.5 {
                return "maintain current — RPE \(formatRPE(latestRPE)) suggests near limit"
            }
            return "maintain current prescription"
        }
    }

    // MARK: - Prompt Formatting

    /// Format distilled athlete states into a compact prompt block for the generation call.
    /// Returns the formatted string and telemetry data.
    static func formatForPrompt(
        states: [ExerciseAthleteState],
        dbSummaryLine: String,
        rawContextChars: Int = 0
    ) -> (prompt: String, telemetry: DistillationTelemetry) {
        var lines: [String] = [
            "DISTILLED ATHLETE STATE (pre-computed from DB — use directly for load/rep decisions):",
            "Database: \(dbSummaryLine)",
            "",
        ]

        var currentDay = ""
        for state in states {
            if state.dayHint.uppercased() != currentDay {
                currentDay = state.dayHint.uppercased()
                lines.append("[\(currentDay)]")
            }

            let sessionLabel = state.sessionCount == 1 ? "1 session" : "\(state.sessionCount) sessions"
            lines.append("  \(state.exerciseName) (\(sessionLabel)):")
            lines.append("    last_rx: \(state.lastPrescription) | perf: \(state.lastPerformance) | RPE: \(state.latestRPE.map { formatRPE($0) } ?? "n/a")")
            lines.append("    trends: load \(state.loadTrend) | RPE \(state.rpeTrend)")
            lines.append("    signal: \(state.progressionSignal) — \(state.progressionReason)")
            lines.append("    -> \(state.recommendation)")
        }

        // Add instruction footer.
        lines.append("")
        lines.append("Use the signals above directly. Do not infer differently from raw data — these are deterministic.")

        let prompt = lines.joined(separator: "\n")
        let telemetry = DistillationTelemetry(
            exercisesDistilled: states.count,
            rawRowsConsumed: states.reduce(0) { $0 + $1.sessionCount },
            distilledPromptChars: prompt.count,
            rawContextChars: rawContextChars,
            compressionRatio: rawContextChars > 0 ? Double(prompt.count) / Double(rawContextChars) : 0
        )

        return (prompt, telemetry)
    }

    // MARK: - Helpers

    private static func formatPrescription(sets: String, reps: String, load: String) -> String {
        var parts: [String] = []
        if !sets.isEmpty && !reps.isEmpty {
            parts.append("\(sets)x\(reps)")
        }
        if !load.isEmpty {
            parts.append("@\(load) kg")
        }
        return parts.isEmpty ? "no prescription" : parts.joined(separator: " ")
    }

    private static func summarizeLog(_ logText: String) -> String {
        let trimmed = logText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "not logged" }

        // Strip RPE since we track it separately.
        let withoutRPE = trimmed.replacingOccurrences(
            of: #"\s*\|?\s*[Rr][Pp][Ee]\s*:?\s*\d+(?:\.\d+)?\s*"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // Truncate to keep compact.
        if withoutRPE.count > 60 {
            return String(withoutRPE.prefix(57)) + "..."
        }
        return withoutRPE.isEmpty ? "logged (no text)" : withoutRPE
    }

    static func formatRPE(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    static func formatLoadValue(_ value: Double) -> String {
        if abs(value - round(value)) < 0.01 {
            return String(Int(round(value)))
        }
        return String(format: "%.1f", value)
    }

    private static func parseLoad(_ value: String) -> Double? {
        let cleaned = value
            .replacingOccurrences(of: "kg", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    /// Compute the next even dumbbell load step (round up to nearest even number + 2).
    private static func nextEvenDBLoad(_ current: Double) -> Double {
        let rounded = ceil(current)
        let even = rounded.truncatingRemainder(dividingBy: 2) == 0 ? rounded : rounded + 1
        return even + 2
    }
}
