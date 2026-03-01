import Foundation
import WorkoutCore
import WorkoutIntegrations
import WorkoutPersistence

extension LiveAppGateway {
    struct RepairOutcome {
        var planText: String
        var lockedApplied: Int
        var rangeCollapsed: Int
        var anchorInsertions: Int
    }

    func generatePlan(
        input: PlanGenerationInput,
        onProgress: ((GenerationProgressUpdate) -> Void)?
    ) async throws -> String {
        let config = try requireGenerationSetup()
        let progressCallback = ThreadSafeBox(onProgress)
        let emitFromStream: @Sendable (GenerationProgressUpdate) -> Void = { update in
            Task { @MainActor in
                progressCallback.get()?(update)
            }
        }
        func emit(
            _ stage: GenerationProgressStage,
            _ message: String,
            streamedCharacters: Int? = nil,
            inputTokens: Int? = nil,
            outputTokens: Int? = nil,
            previewTail: String? = nil,
            correctionAttempt: Int? = nil
        ) {
            progressCallback.get()?(
                GenerationProgressUpdate(
                    stage: stage,
                    message: message,
                    streamedCharacters: streamedCharacters,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    previewTail: previewTail,
                    correctionAttempt: correctionAttempt
                )
            )
        }
        emit(.preparing, "Preparing generation inputs and setup checks.")

        let fortInputMap = [
            "Monday": input.monday,
            "Wednesday": input.wednesday,
            "Friday": input.friday,
        ]
        let (fortContext, fortMetadata) = buildFortCompilerContext(dayTextMap: fortInputMap, sectionOverrides: input.fortSectionOverrides)
        emit(.normalizingFort, "Fort input normalized locally before model request.")
        let aliases = loadExerciseAliases()
        let priorSupplemental = try await loadPriorSupplementalForProgression(config: config)
        let progressionRules = buildProgressionDirectives(priorSupplemental: priorSupplemental)
        let planDirectives = progressionRules.map { $0.asPlanDirective() }
        let directivesBlock = formatDirectivesForPrompt(progressionRules)
        let oneRepMaxes = loadOneRepMaxesFromConfig()

        // ── Two-pass: exercise selection → targeted DB context ──────────────────
        // Pass 1: ask Claude to enumerate which exercises it will program on
        // Tue/Thu/Sat. This is a cheap call (~200-300 output tokens). We use the
        // result to pull targeted DB history for ONLY those exercises, avoiding
        // the noise of fetching 40 generic recent rows that may not even be used.
        let anthropicPass1 = integrations.makeAnthropicClient(
            apiKey: config.anthropicAPIKey,
            model: "claude-sonnet-4-6",
            maxTokens: 300
        )
        let dbContext: String
        do {
            emit(.preparing, "Pass 1: selecting supplemental exercises for targeted DB context.")
            let selectionPrompt = PromptBuilder.buildExerciseSelectionPrompt(input: input, fortContext: fortContext)
            let pass1Result = try await anthropicPass1.generatePlan(
                systemPrompt: nil,
                userPrompt: selectionPrompt,
                onEvent: nil
            )
            let selected = parseSelectedExercises(from: pass1Result.text)
            if !selected.isEmpty,
               let targeted = buildTargetedDBContext(for: selected) {
                let exerciseCount = selected.values.reduce(0) { $0 + $1.count }
                emit(.preparing, "Pass 1 complete: \(exerciseCount) exercises selected, targeted DB context built.")
                dbContext = targeted
            } else {
                // Parsed OK but no DB history found — fall back to generic context.
                emit(.preparing, "Pass 1: no matching DB history for selected exercises, falling back to generic context.")
                dbContext = buildRecentDBContext()
            }
        } catch {
            // Pass 1 network error or any other failure — fall back gracefully.
            emit(.preparing, "Pass 1 failed (\(error.localizedDescription)), falling back to generic DB context.")
            dbContext = buildRecentDBContext()
        }
        // ────────────────────────────────────────────────────────────────────────

        let prompt = PromptBuilder.buildGenerationPrompt(
            input: input,
            fortContext: fortContext,
            dbContext: dbContext,
            progressionDirectivesBlock: directivesBlock,
            oneRepMaxes: oneRepMaxes
        )

        let anthropic = integrations.makeAnthropicClient(
            apiKey: config.anthropicAPIKey,
            model: "claude-sonnet-4-6",
            maxTokens: 8192
        )

        emit(.requestingModel, "Requesting plan from Anthropic.")
        let streamedCharsBox = ThreadSafeBox(0)
        let latestInputTokensBox = ThreadSafeBox<Int?>(nil)
        let latestOutputTokensBox = ThreadSafeBox<Int?>(nil)
        let latestPreviewTailBox = ThreadSafeBox("")
        let generation = try await anthropic.generatePlan(
            systemPrompt: "You generate deterministic weekly workout plans in strict markdown format.",
            userPrompt: prompt,
            onEvent: { event in
                switch event {
                case .requestStarted:
                    emitFromStream(
                        GenerationProgressUpdate(
                            stage: .streamingResponse,
                            message: "Model stream opened."
                        )
                    )
                case .messageStarted(_, let inputTokens):
                    latestInputTokensBox.set(inputTokens)
                    emitFromStream(
                        GenerationProgressUpdate(
                            stage: .streamingResponse,
                            message: "Model response started.",
                            streamedCharacters: streamedCharsBox.get(),
                            inputTokens: latestInputTokensBox.get()
                        )
                    )
                case .textDelta(let chunk, let totalCharacters):
                    streamedCharsBox.set(totalCharacters)
                    var previewTail = latestPreviewTailBox.get() + chunk
                    if previewTail.count > 320 {
                        previewTail = String(previewTail.suffix(320))
                    }
                    latestPreviewTailBox.set(previewTail)
                    emitFromStream(
                        GenerationProgressUpdate(
                            stage: .streamingResponse,
                            message: "Streaming model response…",
                            streamedCharacters: streamedCharsBox.get(),
                            inputTokens: latestInputTokensBox.get(),
                            outputTokens: latestOutputTokensBox.get(),
                            previewTail: previewTail
                        )
                    )
                case .messageDelta(_, let outputTokens):
                    if let outputTokens {
                        latestOutputTokensBox.set(outputTokens)
                    }
                    emitFromStream(
                        GenerationProgressUpdate(
                            stage: .streamingResponse,
                            message: "Streaming model response…",
                            streamedCharacters: streamedCharsBox.get(),
                            inputTokens: latestInputTokensBox.get(),
                            outputTokens: latestOutputTokensBox.get(),
                            previewTail: latestPreviewTailBox.get()
                        )
                    )
                case .messageStopped:
                    emitFromStream(
                        GenerationProgressUpdate(
                            stage: .validating,
                            message: "Model stream complete. Running deterministic repairs and validation.",
                            streamedCharacters: streamedCharsBox.get(),
                            inputTokens: latestInputTokensBox.get(),
                            outputTokens: latestOutputTokensBox.get(),
                            previewTail: latestPreviewTailBox.get()
                        )
                    )
                }
            }
        )
        let streamedChars = streamedCharsBox.get()
        let latestInputTokens = latestInputTokensBox.get()
        let latestOutputTokens = latestOutputTokensBox.get()
        var plan = PlanRepairs.stripPlanPreamble(generation.text)
        var repairResult = applyDeterministicRepairs(
            planText: plan,
            progressionDirectives: planDirectives,
            fortMetadata: fortMetadata,
            exerciseAliases: aliases
        )
        plan = repairResult.planText

        var validation = validatePlan(plan, progressionDirectives: planDirectives)
        var fidelity = validateFortFidelity(
            planText: plan,
            metadata: fortMetadata,
            exerciseAliases: aliases
        )

        var unresolved: [any ViolationDescribing] = validation.violations + fidelity.violations
        var correctionAttempts = 0
        while !unresolved.isEmpty, correctionAttempts < 2 {
            emit(
                .correcting,
                "Applying correction pass \(correctionAttempts + 1) for \(unresolved.count) unresolved issue(s).",
                streamedCharacters: streamedChars,
                inputTokens: latestInputTokens ?? generation.inputTokens,
                outputTokens: latestOutputTokens ?? generation.outputTokens,
                correctionAttempt: correctionAttempts + 1
            )
            let correctionPrompt = PromptBuilder.buildCorrectionPrompt(
                plan: plan,
                unresolvedViolations: unresolved,
                fortCompilerContext: fortContext,
                fortFidelitySummary: fidelity.summary
            )
            let correction = try await anthropic.generatePlan(
                systemPrompt: nil,
                userPrompt: correctionPrompt,
                onEvent: nil
            )
            plan = PlanRepairs.stripPlanPreamble(correction.text)
            let correctionRepair = applyDeterministicRepairs(
                planText: plan,
                progressionDirectives: planDirectives,
                fortMetadata: fortMetadata,
                exerciseAliases: aliases
            )
            repairResult.lockedApplied += correctionRepair.lockedApplied
            repairResult.rangeCollapsed += correctionRepair.rangeCollapsed
            repairResult.anchorInsertions += correctionRepair.anchorInsertions
            plan = correctionRepair.planText

            validation = validatePlan(plan, progressionDirectives: planDirectives)
            fidelity = validateFortFidelity(
                planText: plan,
                metadata: fortMetadata,
                exerciseAliases: aliases
            )
            unresolved = validation.violations + fidelity.violations
            correctionAttempts += 1
        }

        emit(
            .writingOutputs,
            "Writing local output and preparing Google Sheets rows.",
            streamedCharacters: streamedChars,
            inputTokens: latestInputTokens ?? generation.inputTokens,
            outputTokens: latestOutputTokens ?? generation.outputTokens
        )
        let validationSummary = """
        \(validation.summary) \(fidelity.summary) \
        Locked directives applied: \(repairResult.lockedApplied). \
        Range collapses: \(repairResult.rangeCollapsed). \
        Fort anchors auto-inserted: \(repairResult.anchorInsertions). \
        Correction attempts: \(correctionAttempts). \
        Unresolved violations: \(unresolved.count).
        """

        let sheetDateGuard = sanitizedSheetReferenceDate(nowProvider())
        let sheetName = weeklySheetName(referenceDate: sheetDateGuard.date)
        let localFile = try savePlanLocally(
            planText: plan,
            sheetName: sheetName,
            validationSummary: validationSummary,
            fidelitySummary: fidelity.summary
        )

        let rows = PlanTextParser.makeSheetRows(
            planText: plan,
            validationSummary: validationSummary,
            fidelitySummary: fidelity.summary,
            generatedAtISO: isoDateTime(nowProvider())
        )

        var sheetStatus = "Google Sheets write skipped (auth token unavailable)."
        switch planWriteMode {
        case .normal:
            if let sheetsClient = try? await makeSheetsClient(config: config) {
                emit(.syncingDatabase, "Writing plan to Google Sheets.")
                do {
                    try await sheetsClient.writeWeeklyPlanRows(
                        sheetName: sheetName,
                        rows: rows,
                        archiveExisting: true
                    )
                    sheetStatus = "Google Sheets updated successfully."
                } catch {
                    sheetStatus = "Google Sheets write failed: \(error.localizedDescription)"
                }
            }
        case .localOnly:
            sheetStatus = "Google Sheets write skipped (local-only mode)."
        }

        emit(
            .completed,
            "Generation completed successfully.",
            streamedCharacters: streamedChars,
            inputTokens: latestInputTokens ?? generation.inputTokens,
            outputTokens: latestOutputTokens ?? generation.outputTokens
        )

        return """
        Generated \(sheetName).
        Local file: \(localFile.lastPathComponent)
        \(sheetStatus)
        Date guard: \(sheetDateGuard.wasSanitized ? "Applied (far-future/past date replaced with current week)." : "Not needed.")
        Validation: \(validationSummary)
        Fort fidelity: \(fidelity.summary)
        """
    }

    func loadPriorSupplementalForProgression(config: NativeAppConfiguration) async throws -> [String: [PriorSupplementalExercise]] {
        guard let sheetsClient = try? await makeSheetsClient(config: config) else {
            return [:]
        }

        let sheetNames = try await sheetsClient.fetchSheetNames()
        guard let preferredSheet = preferredWeeklyPlanSheetName(sheetNames) else {
            return [:]
        }

        let values = try await sheetsClient.readSheetAtoH(sheetName: preferredSheet)
        let supplemental = GoogleSheetsClient.parseSupplementalWorkouts(values: values)
        var output: [String: [PriorSupplementalExercise]] = [:]
        for day in ["Tuesday", "Thursday", "Saturday"] {
            output[day] = (supplemental[day] ?? []).map { row in
                PriorSupplementalExercise(
                    exercise: row.exercise,
                    reps: row.reps,
                    load: row.load,
                    log: row.log
                )
            }
        }
        return output
    }

    // MARK: - Two-Pass Generation Helpers

    /// Parse the Pass 1 response into a dict keyed by uppercase day name.
    /// Returns an empty dict on parse failure so the caller can fall back gracefully.
    func parseSelectedExercises(from text: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        let dayKeys = ["TUESDAY", "THURSDAY", "SATURDAY"]

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            // Match "Tuesday: ...", "thursday: ...", etc.
            guard let colonRange = trimmed.range(of: ":") else {
                continue
            }
            let dayRaw = String(trimmed[..<colonRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard dayKeys.contains(dayRaw) else {
                continue
            }

            let exercisePart = String(trimmed[colonRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if exercisePart.isEmpty {
                continue
            }

            let exercises = exercisePart
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if !exercises.isEmpty {
                result[dayRaw] = exercises
            }
        }

        // Only return a result if all three days parsed successfully.
        let allParsed = dayKeys.allSatisfy { result[$0] != nil && !(result[$0]!.isEmpty) }
        return allParsed ? result : [:]
    }

    /// Build targeted DB context for ONLY the exercises selected in Pass 1.
    /// Mirrors the Python `build_targeted_db_context()` logic.
    /// Returns nil if no targeted history is found (caller should fall back to generic context).
    func buildTargetedDBContext(
        for selectedExercises: [String: [String]],
        maxChars: Int = 3200,
        logsPerExercise: Int = 4
    ) -> String? {
        guard let database = try? openDatabase() else {
            return nil
        }

        // Collect all exercise names across all three supplemental days, deduplicated.
        let allNames = Array(Set(selectedExercises.values.flatMap { $0 }))
        guard !allNames.isEmpty else {
            return nil
        }

        let normalizer = getNormalizer()

        // Build a deduplicated list of (displayName, normalizedKey) pairs.
        var seen = Set<String>()
        var targets: [(displayName: String, normalizedKey: String)] = []
        for name in allNames {
            let norm = normalizer.canonicalKey(name)
            guard !norm.isEmpty, !seen.contains(norm) else {
                continue
            }
            seen.insert(norm)
            targets.append((displayName: normalizer.canonicalName(name), normalizedKey: norm))
        }

        guard !targets.isEmpty else {
            return nil
        }

        // Fetch logs for just these exercises.
        let normalizedKeys = targets.map { $0.normalizedKey }
        guard let rows = try? database.fetchTargetedLogContextRows(
            normalizedNames: normalizedKeys,
            logsPerExercise: logsPerExercise
        ), !rows.isEmpty else {
            return nil
        }

        // Group rows by normalizedKey so we can emit one block per exercise.
        var rowsByNorm: [String: [PersistedTargetedLogContextRow]] = [:]
        for row in rows {
            rowsByNorm[row.normalizedName, default: []].append(row)
        }

        // Build global DB summary header line.
        let dbSummaryLine: String
        if let summary = try? database.countSummary() {
            let logCount = summary.exerciseLogs
            let rpeCount = summary.logsWithRPE
            let rpePct = logCount > 0 ? (Double(rpeCount) / Double(logCount) * 100) : 0.0
            dbSummaryLine = "\(summary.exercises) exercises | \(summary.sessions) sessions | \(logCount) logs | RPE coverage \(String(format: "%.1f", rpePct))%"
        } else {
            dbSummaryLine = "DB summary unavailable."
        }

        var lines: [String] = [
            "EXERCISE HISTORY FROM DATABASE:",
            "- DB: \(dbSummaryLine).",
            "- Recent prescription + performance data for selected exercises:",
        ]

        func fitsBudget(_ candidate: [String]) -> Bool {
            return maxChars <= 0 || candidate.joined(separator: "\n").count <= maxChars
        }

        var added = 0
        for (displayName, normalizedKey) in targets {
            guard let exerciseRows = rowsByNorm[normalizedKey], !exerciseRows.isEmpty else {
                continue
            }

            let compactEntries: [String] = exerciseRows.map { row in
                let dayOrDate = row.sessionDateISO.isEmpty ? row.dayLabel : row.sessionDateISO
                var rx = ""
                if !row.sets.isEmpty && !row.reps.isEmpty {
                    rx = "\(row.sets)x\(row.reps)"
                    if !row.load.isEmpty {
                        rx += " @\(row.load)"
                    }
                } else if !row.load.isEmpty {
                    rx = "@\(row.load)"
                }

                var logPart = String(row.logText.prefix(70))
                if let rpe = row.parsedRPE, !row.logText.lowercased().contains("rpe") {
                    let rpeStr = rpe.truncatingRemainder(dividingBy: 1) == 0
                        ? String(format: "%.0f", rpe)
                        : String(format: "%.1f", rpe)
                    logPart = logPart.isEmpty ? "RPE \(rpeStr)" : "\(logPart) | RPE \(rpeStr)"
                }

                var entry = "\(dayOrDate): \(rx)"
                if !logPart.isEmpty {
                    entry += " [\(logPart)]"
                }
                return entry
            }

            let candidateLine = "  - [DB] \(displayName) -> " + compactEntries.joined(separator: " || ")
            let candidateLines = lines + [candidateLine]
            if !fitsBudget(candidateLines) {
                lines.append("- Context truncated to stay within prompt budget.")
                break
            }

            lines.append(candidateLine)
            added += 1
        }

        if added == 0 {
            return nil
        }

        let tail = "- Use this for load/rep reference; prior-week sheet remains primary for immediate progression."
        if fitsBudget(lines + [tail]) {
            lines.append(tail)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Generic DB Context (fallback)

    func buildRecentDBContext(maxRows: Int = 40, maxChars: Int = 3200) -> String {
        guard let database = try? openDatabase(),
              let rows = try? database.fetchRecentLogContextRows(limit: maxRows),
              !rows.isEmpty
        else {
            return "No recent DB logs available."
        }

        var lines: [String] = ["TARGETED DB CONTEXT (RECENT LOGS):"]
        for row in rows {
            let line = "- \(row.sessionDateISO) | \(row.dayLabel) | \(row.exerciseName) | \(row.sets)x\(row.reps) @ \(row.load)kg | log: \(row.logText)"
            lines.append(line)
        }
        let joined = lines.joined(separator: "\n")
        if joined.count <= maxChars {
            return joined
        }
        return String(joined.prefix(maxChars))
    }

    func applyDeterministicRepairs(
        planText: String,
        progressionDirectives: [ProgressionDirective],
        fortMetadata: FortCompilerMetadata?,
        exerciseAliases: [String: String]
    ) -> RepairOutcome {
        var repaired = planText
        repaired = PlanRepairs.applyExerciseSwaps(repaired, aliases: exerciseAliases)
        repaired = PlanRepairs.enforceEvenDumbbellLoads(repaired)

        let locked = applyLockedDirectivesToPlan(planText: repaired, directives: progressionDirectives)
        repaired = locked.0

        let rangeRepair = PlanRepairs.collapseRangesInPrescriptionLines(repaired)
        repaired = rangeRepair.planText

        let anchorRepair = repairPlanFortAnchors(
            planText: repaired,
            metadata: fortMetadata,
            exerciseAliases: exerciseAliases
        )
        repaired = PlanRepairs.canonicalizeExerciseNames(anchorRepair.0)

        return RepairOutcome(
            planText: repaired,
            lockedApplied: locked.1,
            rangeCollapsed: rangeRepair.collapsedCount,
            anchorInsertions: anchorRepair.1.inserted
        )
    }
}
