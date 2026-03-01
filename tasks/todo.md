# Session Plan - LiveAppGateway Structural Refactor (2026-03-01)

## Checklist
- [x] Confirm this session plan with the user before any source-code changes.
- [x] Baseline verification: `cd native/SamsWorkoutNative && swift test` (expect 156 tests, 0 failures).
- [x] Step 1: Create `Sources/WorkoutDesktopApp/PlanRepairs.swift`; move repair functions and private regex helpers; update call sites; run `swift test`.
- [x] Step 2: Create `Sources/WorkoutDesktopApp/PlanTextParser.swift`; move parsing functions + regex statics; update call sites; run `swift test`.
- [x] Step 3: Create `Sources/WorkoutDesktopApp/PromptBuilder.swift`; move prompt builders; update call sites; run `swift test`.
- [x] Step 4: Create `Sources/WorkoutDesktopApp/LiveAppGateway+Analytics.swift`; move analytics and InBody CRUD private extension methods; run `swift test`.
- [x] Step 5: Create `Sources/WorkoutDesktopApp/LiveAppGateway+Database.swift`; move DB lifecycle methods; run `swift test`.
- [x] Step 6: Create `Sources/WorkoutDesktopApp/LiveAppGateway+Plans.swift`; move plan snapshot/local I/O/aliases/date naming methods; run `swift test`.
- [x] Step 7: Create `Sources/WorkoutDesktopApp/LiveAppGateway+Generation.swift`; move generation orchestration and helpers; run `swift test`.
- [x] Step 8: Trim `Sources/WorkoutDesktopApp/LiveAppGateway.swift` to keep only required core elements; run `swift test`.
- [x] Step 9: Update test accessor wrapper bodies in `LiveAppGateway.swift` to delegate to `PlanTextParser`, `PlanRepairs`, and `PromptBuilder` as needed; run `swift test`.
- [x] Final verification: `bash scripts/build_local_app.sh`.
- [x] Final verification: `wc -l Sources/WorkoutDesktopApp/LiveAppGateway.swift` (target around 400 lines).
- [x] Final verification: `grep -rn "func buildGenerationPrompt" Sources/WorkoutDesktopApp` (must appear only in `PromptBuilder.swift`).
- [x] Update `progress.txt` with completed work (phase reference + outcomes + validation commands).
- [x] Capture review notes below and summarize dead code candidates for explicit user decision.

## Review (fill in at end of session)
- Findings:
- Structural refactor completed per requested split with no public protocol signature changes.
- Behavior/API regression check:
- `swift test` remained green after each extraction step (`156 tests`, `3 skipped`, `0 failures` each run).
- Dead code candidates:
- None identified during this structural move.
- Validation results:
- Baseline and per-step verification complete (`swift test` repeated after every step).
- `bash scripts/build_local_app.sh` succeeded.
- `wc -l Sources/WorkoutDesktopApp/LiveAppGateway.swift` = `376`.
- `grep -rn "func buildGenerationPrompt" Sources/WorkoutDesktopApp` reports only `PromptBuilder.swift`.
- Risks or follow-ups:
- Access-control scope was widened from file-private to type/module-visible for split methods/properties to support multi-file extensions; this is structural and non-behavioral but worth noting for future encapsulation tightening if desired.
