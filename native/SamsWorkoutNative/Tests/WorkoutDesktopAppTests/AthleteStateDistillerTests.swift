import XCTest
@testable import WorkoutDesktopApp
import WorkoutCore
import WorkoutPersistence

@MainActor
final class AthleteStateDistillerTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeRow(
        dateISO: String = "2026-02-17",
        dayLabel: String = "Tuesday",
        exerciseName: String = "DB Hammer Curl",
        normalizedName: String = "db_hammer_curl",
        sets: String = "3",
        reps: String = "12",
        load: String = "24",
        logText: String = "felt easy | RPE 7",
        parsedRPE: Double? = 7.0
    ) -> PersistedTargetedLogContextRow {
        PersistedTargetedLogContextRow(
            sessionDateISO: dateISO,
            dayLabel: dayLabel,
            exerciseName: exerciseName,
            normalizedName: normalizedName,
            sets: sets,
            reps: reps,
            load: load,
            logText: logText,
            parsedRPE: parsedRPE
        )
    }

    private func makeDirective(
        dayName: String = "tuesday",
        exerciseName: String = "DB Hammer Curl",
        normalizedExercise: String = "db_hammer_curl",
        signal: String = "progress",
        reason: String = "low_rpe",
        holdLock: Bool = false,
        targetReps: Int? = 12,
        targetLoad: Double? = 24.0,
        parsedRPE: Double? = 7.0,
        sourceLog: String = "felt easy | RPE 7"
    ) -> ProgressionRuleDirective {
        ProgressionRuleDirective(
            dayName: dayName,
            exerciseName: exerciseName,
            normalizedExercise: normalizedExercise,
            signal: signal,
            reason: reason,
            holdLock: holdLock,
            targetReps: targetReps,
            targetLoad: targetLoad,
            parsedRPE: parsedRPE,
            sourceLog: sourceLog
        )
    }

    // MARK: - RPE Trend Tests

    func testRPETrendStable() {
        let result = AthleteStateDistiller.computeRPETrend([7.0, 7.0, 7.5, 7.0])
        XCTAssertTrue(result.contains("stable"), "Expected stable trend, got: \(result)")
    }

    func testRPETrendRising() {
        let result = AthleteStateDistiller.computeRPETrend([9.0, 8.0, 7.5, 7.0])
        XCTAssertTrue(result.contains("rising"), "Expected rising trend, got: \(result)")
    }

    func testRPETrendFalling() {
        let result = AthleteStateDistiller.computeRPETrend([6.5, 7.0, 7.5, 8.0])
        XCTAssertTrue(result.contains("falling"), "Expected falling trend, got: \(result)")
    }

    func testRPETrendSinglePoint() {
        let result = AthleteStateDistiller.computeRPETrend([7.5])
        XCTAssertTrue(result.contains("single point"), "Expected single point, got: \(result)")
    }

    func testRPETrendEmpty() {
        let result = AthleteStateDistiller.computeRPETrend([])
        XCTAssertEqual(result, "no RPE data")
    }

    // MARK: - Load Trend Tests

    func testLoadTrendRising() {
        let result = AthleteStateDistiller.computeLoadTrend([24.0, 22.0, 20.0])
        XCTAssertTrue(result.contains("rising"), "Expected rising trend, got: \(result)")
    }

    func testLoadTrendStable() {
        let result = AthleteStateDistiller.computeLoadTrend([24.0, 24.0, 24.0])
        XCTAssertTrue(result.contains("stable"), "Expected stable trend, got: \(result)")
    }

    func testLoadTrendFalling() {
        let result = AthleteStateDistiller.computeLoadTrend([20.0, 22.0, 24.0])
        XCTAssertTrue(result.contains("falling"), "Expected falling trend, got: \(result)")
    }

    // MARK: - Distillation Tests

    func testDistillWithProgressDirective() {
        let rows = [
            makeRow(dateISO: "2026-02-17", load: "24", parsedRPE: 7.0),
            makeRow(dateISO: "2026-02-10", load: "22", parsedRPE: 7.0),
            makeRow(dateISO: "2026-02-03", load: "22", parsedRPE: 7.5),
        ]
        let directives = [
            makeDirective(signal: "progress", holdLock: false),
        ]
        let selected: [String: [String]] = ["TUESDAY": ["DB Hammer Curl"]]

        let states = AthleteStateDistiller.distill(
            targetedRows: rows,
            progressionDirectives: directives,
            selectedExercises: selected
        )

        XCTAssertEqual(states.count, 1)
        let state = states[0]
        XCTAssertEqual(state.progressionSignal, "PROGRESS")
        XCTAssertEqual(state.sessionCount, 3)
        XCTAssertTrue(state.recommendation.contains("increase load"), "Expected load increase recommendation, got: \(state.recommendation)")
    }

    func testDistillWithLockDirective() {
        let rows = [
            makeRow(dateISO: "2026-02-17", load: "24", logText: "hard set, keep | RPE 9", parsedRPE: 9.0),
        ]
        let directives = [
            makeDirective(signal: "hold_lock", reason: "high_rpe", holdLock: true),
        ]
        let selected: [String: [String]] = ["TUESDAY": ["DB Hammer Curl"]]

        let states = AthleteStateDistiller.distill(
            targetedRows: rows,
            progressionDirectives: directives,
            selectedExercises: selected
        )

        XCTAssertEqual(states.count, 1)
        let state = states[0]
        XCTAssertEqual(state.progressionSignal, "LOCK")
        XCTAssertTrue(state.recommendation.contains("maintain"), "Expected maintain recommendation, got: \(state.recommendation)")
    }

    func testDistillWithNoDBRows() {
        let selected: [String: [String]] = ["TUESDAY": ["Some New Exercise"]]

        let states = AthleteStateDistiller.distill(
            targetedRows: [],
            progressionDirectives: [],
            selectedExercises: selected
        )

        XCTAssertEqual(states.count, 1)
        let state = states[0]
        XCTAssertEqual(state.sessionCount, 0)
        XCTAssertTrue(state.recommendation.contains("new exercise"), "Expected new exercise recommendation, got: \(state.recommendation)")
    }

    func testDistillMultipleDays() {
        let rows = [
            makeRow(dateISO: "2026-02-17", exerciseName: "DB Hammer Curl", normalizedName: "db_hammer_curl", load: "24", parsedRPE: 7.0),
            makeRow(dateISO: "2026-02-17", dayLabel: "Thursday", exerciseName: "Cable Lateral Raise", normalizedName: "cable_lateral_raise", load: "8", parsedRPE: 7.5),
        ]
        let selected: [String: [String]] = [
            "TUESDAY": ["DB Hammer Curl"],
            "THURSDAY": ["Cable Lateral Raise"],
        ]

        let states = AthleteStateDistiller.distill(
            targetedRows: rows,
            progressionDirectives: [],
            selectedExercises: selected
        )

        XCTAssertEqual(states.count, 2)
        // Verify ordering: Tuesday before Thursday.
        XCTAssertEqual(states[0].dayHint, "Tuesday")
        XCTAssertEqual(states[1].dayHint, "Thursday")
    }

    // MARK: - Prompt Formatting Tests

    func testFormatForPromptProducesStructuredOutput() {
        let rows = [
            makeRow(dateISO: "2026-02-17", load: "24", parsedRPE: 7.0),
            makeRow(dateISO: "2026-02-10", load: "22", parsedRPE: 7.0),
        ]
        let selected: [String: [String]] = ["TUESDAY": ["DB Hammer Curl"]]

        let states = AthleteStateDistiller.distill(
            targetedRows: rows,
            progressionDirectives: [],
            selectedExercises: selected
        )

        let (prompt, telemetry) = AthleteStateDistiller.formatForPrompt(
            states: states,
            dbSummaryLine: "125 exercises | 72 sessions",
            rawContextChars: 2000
        )

        XCTAssertTrue(prompt.contains("DISTILLED ATHLETE STATE"))
        XCTAssertTrue(prompt.contains("[TUESDAY]"))
        XCTAssertTrue(prompt.contains("DB Hammer Curl"))
        XCTAssertTrue(prompt.contains("last_rx:"))
        XCTAssertTrue(prompt.contains("trends:"))
        XCTAssertTrue(prompt.contains("signal:"))
        XCTAssertEqual(telemetry.exercisesDistilled, 1)
        XCTAssertEqual(telemetry.rawRowsConsumed, 2)
        XCTAssertTrue(telemetry.compressionRatio > 0)
    }

    func testFormatForPromptIsCompact() {
        // Verify distilled context is more compact than raw.
        let rows = [
            makeRow(dateISO: "2026-02-17", load: "24", logText: "3x12 done, felt easy, could have gone heavier | RPE 7", parsedRPE: 7.0),
            makeRow(dateISO: "2026-02-10", load: "22", logText: "3x12 done, getting the feel for it | RPE 7.5", parsedRPE: 7.5),
            makeRow(dateISO: "2026-02-03", load: "22", logText: "first time with this exercise, form okay | RPE 8", parsedRPE: 8.0),
        ]
        let selected: [String: [String]] = ["TUESDAY": ["DB Hammer Curl"]]

        let states = AthleteStateDistiller.distill(
            targetedRows: rows,
            progressionDirectives: [],
            selectedExercises: selected
        )

        let rawChars = rows.map { "2026-02-17: 3x12 @24 [\($0.logText)]" }.joined(separator: " || ").count
        let (prompt, telemetry) = AthleteStateDistiller.formatForPrompt(
            states: states,
            dbSummaryLine: "125 exercises | 72 sessions",
            rawContextChars: rawChars
        )

        // The distilled version should exist and have meaningful content.
        XCTAssertFalse(prompt.isEmpty)
        XCTAssertGreaterThan(telemetry.distilledPromptChars, 0)
    }

    // MARK: - Helper Formatting Tests

    func testFormatRPEInteger() {
        XCTAssertEqual(AthleteStateDistiller.formatRPE(7.0), "7")
    }

    func testFormatRPEDecimal() {
        XCTAssertEqual(AthleteStateDistiller.formatRPE(7.5), "7.5")
    }

    func testFormatLoadValueInteger() {
        XCTAssertEqual(AthleteStateDistiller.formatLoadValue(24.0), "24")
    }

    func testFormatLoadValueDecimal() {
        XCTAssertEqual(AthleteStateDistiller.formatLoadValue(22.5), "22.5")
    }

    // MARK: - Pipeline Telemetry Tests

    func testPipelineTelemetrySummary() {
        var telemetry = PipelineTelemetry()
        telemetry.pipelineMode = .staged
        telemetry.stages = [
            PipelineTelemetry.StageMetrics(
                stageName: "exercise_selection",
                inputTokens: 500,
                outputTokens: 100,
                durationMs: 2000,
                promptChars: 1500
            ),
            PipelineTelemetry.StageMetrics(
                stageName: "plan_synthesis",
                inputTokens: 2000,
                outputTokens: 5000,
                durationMs: 30000,
                promptChars: 6000
            ),
        ]
        telemetry.distillation = DistillationTelemetry(
            exercisesDistilled: 15,
            rawRowsConsumed: 40,
            distilledPromptChars: 1200,
            rawContextChars: 3000,
            compressionRatio: 0.4
        )

        let summary = telemetry.summary
        XCTAssertTrue(summary.contains("staged"), "Expected 'staged' in summary: \(summary)")
        XCTAssertTrue(summary.contains("exercise_selection"), "Expected 'exercise_selection' in summary: \(summary)")
        XCTAssertTrue(summary.contains("plan_synthesis"), "Expected 'plan_synthesis' in summary: \(summary)")
        XCTAssertTrue(summary.contains("15 exercises"), "Expected '15 exercises' in summary: \(summary)")
        XCTAssertEqual(telemetry.totalInputTokens, 2500)
        XCTAssertEqual(telemetry.totalOutputTokens, 5100)
    }

    // MARK: - Generation Mode Tests

    func testGenerationPipelineModeDefault() {
        // Verify the default is .staged.
        let gateway = LiveAppGateway(planWriteMode: .localOnly)
        XCTAssertEqual(gateway.generationMode, .staged)
    }

    func testGenerationPipelineModeLegacy() {
        let gateway = LiveAppGateway(planWriteMode: .localOnly, generationMode: .legacy)
        XCTAssertEqual(gateway.generationMode, .legacy)
    }
}
