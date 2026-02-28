# Session Todo - 2026-02-28 - Fort Normalizer + SSE UX Hardening

Status: Complete
Owner: Codex

## Objectives

- Fix Fort conversion reliability for changing 4-week Fort cycles without hardcoding fragile aliases.
- Improve SSE generation streaming stability and generation UX clarity in native macOS app.
- Keep Python and Swift parser behavior in parity where applicable.

## Assumptions Confirmed by User Intent

1. Work should continue autonomously while user is away.
2. Scope includes both generation correctness and streaming UX, not only one bug fix.
3. Backward compatibility with existing saved plans/sheet schema (A:H) must be preserved.

## Plan

- [x] Audit current Fort parser, correction loop, and SSE pipeline end-to-end.
- [x] Design 10-15 candidate robustness strategies for changing Fort cycles.
- [x] Evaluate candidates against deterministic correctness, complexity, and regression risk.
- [x] Select best architecture and define migration path.
- [x] Implement Fort pre-normalization pipeline in native app before API generation.
- [x] Implement SSE transport/parser hardening and richer progress UX states.
- [x] Add regression tests (Swift + Python parity where needed).
- [x] Run focused and broad test suites.
- [x] Update progress.txt with outcomes, risks, and next steps.
- [x] Add review notes + dead-code check.

## Review

- Chosen architecture: deterministic hybrid normalizer (rule-based section aliasing + dynamic unknown-header inference + exercise-semantic cues + positional fallback) implemented in Swift and Python parity paths.
- Fort parser hardening shipped:
  - Breakthrough/Test-week alias coverage.
  - Dynamic unknown section inference for changing cycle headers.
  - Metadata/noise filtering and COMPLETE-boundary handling.
  - Empty-section rank/anchor stabilization.
- Supplemental guardrails shipped:
  - Validator now flags missing/underfilled Tue/Thu/Sat supplemental days (`<3` exercises).
  - Validator now also flags Fort section headers/noise leaked as exercises (`fort_header_as_exercise`).
  - Prompt constraints updated to enforce minimum supplemental density.
- SSE + UX hardening shipped:
  - Anthropic SSE parser now handles framed events robustly (event/data buffering + frame flush on new event and blank lines).
  - Streaming callback events expose request/message lifecycle, text deltas, and token usage.
  - Generation UI now shows stage, streamed chars, token counts, preview tail, and recent progress log.
- Test verification:
  - Focused Swift suites passed:
    - `swift test --filter FortCompilerParityTests`
    - `swift test --filter PlanValidatorParityTests`
    - `swift test --filter WorkoutDesktopAppTests`
    - `swift test --filter WorkoutIntegrationsTests`
  - Focused Python suites passed:
    - `python3 -m unittest tests.test_fort_compiler -v`
    - `python3 -m unittest tests.test_plan_validator -v`
  - Broad Swift suite passed:
    - `swift test` (`144` tests, `3` skipped, `0` failures)
  - Live native integration checks passed:
    - `RUN_LIVE_E2E=1 swift test --filter WorkoutDesktopAppLiveE2ETests/testLiveGenerateWriteLogAndSync`
    - `RUN_LIVE_E2E=1 swift test --filter WorkoutDesktopAppLiveE2ETests`
  - Broad Python discover surfaced one pre-existing unrelated failure:
    - `test_split_squat_maps_to_goblet` in `tests/test_exercise_normalizer.py`
- Dead code check:
  - No new unreachable/dead code introduced in touched files.
