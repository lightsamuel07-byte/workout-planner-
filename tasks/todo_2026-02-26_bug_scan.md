# Session Plan: Native macOS Bug Scan (2026-02-26)

## Scope
- Perform a bug-focused scan for the local macOS native app only (`native/SamsWorkoutNative`).
- Exclude Streamlit/Python web-app flows unless they are directly used by the native runtime.
- Do not implement fixes in this pass unless explicitly requested.

## Plan
- [x] 1. Capture baseline and changed-surface context (`git status`, recent native file changes).
- [x] 2. Run native automated checks:
  - [x] `swift test --filter WorkoutDesktopAppTests --disable-index-store`
  - [x] `swift test --filter WorkoutPersistenceTests --disable-index-store`
  - [x] `swift test --disable-index-store`
  - [x] `RUN_LIVE_E2E=1 swift test --filter WorkoutDesktopAppLiveE2ETests --disable-index-store`
  - [x] `./scripts/build_local_app.sh`
- [x] 3. Perform targeted static review of high-risk native modules:
  - [x] `Sources/WorkoutDesktopApp/AppCoordinator.swift`
  - [x] `Sources/WorkoutDesktopApp/LiveAppGateway.swift`
  - [x] `Sources/WorkoutIntegrations/GoogleSheetsClient.swift`
  - [x] `Sources/WorkoutIntegrations/AuthSessionManager.swift`
  - [x] `Sources/WorkoutPersistence/WorkoutDatabase.swift`
  - [x] `Sources/WorkoutPersistence/WorkoutSyncService.swift`
- [x] 4. Record findings with severity, evidence, and likely user impact.
- [x] 5. Document residual risk/test gaps and recommended next actions.

## Verification Criteria
- Findings are concrete (file + line reference + failure mode).
- No speculative issues without supporting evidence.
- If no bugs are found, explicitly state that and list residual risk areas.

## Review
- Test/build results:
  - `swift test --filter WorkoutDesktopAppTests --disable-index-store`: passed.
  - `swift test --filter WorkoutPersistenceTests --disable-index-store`: passed.
  - `swift test --disable-index-store`: passed (`137` tests, `3` skipped, `0` failures).
  - `RUN_LIVE_E2E=1 swift test --filter WorkoutDesktopAppLiveE2ETests --disable-index-store`: passed (`3` tests, `0` failures).
  - `./scripts/build_local_app.sh`: passed; signed app rebuilt.
- Findings detected:
  1. Local plan fallback logic can incorrectly throw `noPlanData` when dated local plans exist but are outside near-window.
  2. OAuth refresh path can return stale token if token file is expired and missing refresh fields.
- Residual risk:
  - No deterministic regression test currently covers local-plan fallback when only far-dated local plan files exist.
  - No explicit failure-path test for expired OAuth token file missing refresh fields in runtime path.
