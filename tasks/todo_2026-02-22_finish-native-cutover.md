# Session Plan - Swift Native Finish (2026-02-22)

## Checklist
- [x] Re-read required canonical docs and identify active native track scope from latest progress.
- [x] Phase 5 closeout: replace in-memory app gateway with live runtime wiring.
- [x] Implement generation workflow parity:
  - [x] Anthropic call path from setup credentials.
  - [x] Local markdown persistence with archive-before-overwrite behavior.
  - [x] Validation/fidelity summary surfaced in UI status text.
- [x] Implement view/log parity wiring:
  - [x] View plan from local markdown artifacts (primary).
  - [x] Logger writes canonical log format and updates Google Sheets Column H.
  - [x] Logger syncs successful logs to local GRDB.
- [x] Implement analytics/status parity wiring:
  - [x] DB summary and exercise history from GRDB.
  - [x] Dashboard source/status fields from real runtime state.
- [x] Upgrade executable entrypoint to launch native SwiftUI window directly.
- [x] Add/extend tests for live gateway behaviors and critical regressions.
- [x] Run validation after each major phase:
  - [x] `swift build`
  - [x] `swift test`
  - [x] `./scripts/build_local_app.sh`
  - [x] smoke launch built app bundle.
- [x] Update progress tracking docs (`progress.txt`, parity matrix, todo review).

## Review (fill at completion)
- Findings:
  - App shell placeholder behavior was the remaining blocker; runtime was still using in-memory gateway for core workflows.
  - Test stability issue discovered: desktop tests were reading persisted real config from App Support and needed isolated config-store injection.
- Decisions:
  - Added `LiveAppGateway` for production runtime and kept `InMemoryAppGateway` for deterministic tests.
  - Upgraded `main.swift` to a real AppKit entrypoint hosting `NativeWorkoutRootView` so packaged `.app` launches as a native window.
  - Added DB read-side query APIs in `WorkoutPersistence` to support progress/weekly/history/status views without GRDB leakage into UI layer.
- Validation:
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed (`91 tests`, `0 failures`).
  - `./scripts/build_local_app.sh` passed and signed app emitted at `native/SamsWorkoutNative/dist/SamsWorkoutNative.app`.
  - Smoke launch verified via `open .../SamsWorkoutNative.app` with running app process observed.
- Next steps:
  - Finalize progress snapshot updates and runbook notes for day-to-day usage.

### Addendum (OAuth + Prompt Parity)
- Implemented automatic OAuth token refresh for Google Sheets auth:
  - `AuthSessionManager.resolveOAuthAccessToken(...)` now refreshes expired tokens via refresh_token flow and persists updated access token + expiry to token file.
- Implemented stronger Anthropic generation parity in live native gateway:
  - richer rule-complete prompt,
  - progression directives from prior supplemental sheet logs,
  - deterministic repair chain (swaps/even-DB/locked directives/range collapse/Fort anchor repair/canonical naming),
  - correction loop with validator + Fort fidelity feedback.
- Added regression tests:
  - OAuth refresh + non-refresh paths in integration tests.
- Validation rerun:
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` passed.
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed (`93 tests`, `0 failures`).
  - `./scripts/build_local_app.sh` passed.
  - smoke launch of `dist/SamsWorkoutNative.app` passed.
