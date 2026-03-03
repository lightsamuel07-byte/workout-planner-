# TODO — 2026-03-02 — Bidirectional DB↔Sheets Sync Engine (Native)

## ASSUMPTIONS I’M MAKING

1. Implement this in the native Swift app at `native/SamsWorkoutNative`, not the legacy Streamlit Python app.
2. Scope is backend only: no UI redesign, only backend codepaths and tests.
3. We can ship this as an MVP conflict-resolution engine focused on exercise log column `H` reconciliation.
4. Since Google Sheets does not provide per-cell updated timestamps in current flow, conflict resolution will use deterministic local rules + persisted sync state.
5. It is acceptable to trigger this reconciliation during remote plan refresh (`forceRemote`) so behavior is observable without adding new UI controls.

## PLAN

- [x] Add persistence schema for sync state
  - Add migration `v3_log_sync_state` in `WorkoutDatabase`.
  - Add typed DB models/methods for reading/writing row-level sync checkpoints.

- [x] Add backend reconciliation engine
  - Add a dedicated engine in `WorkoutDesktopApp` that compares sheet log vs DB log per `(sheet, day, source_row)`.
  - Implement deterministic merge rules:
    - one-sided change -> propagate changed side
    - two-sided same value -> accept
    - two-sided divergent value -> deterministic tie-break and conflict counting
  - Return a sync report (pulled, pushed, conflicts, unchanged).

- [x] Integrate into live gateway lifecycle
  - Run reconciliation when remote snapshot is loaded with `forceRemote = true`.
  - Keep existing `loadPlanSnapshot` return contract unchanged.

- [x] Add/extend tests
  - Persistence tests for sync-state table read/write.
  - App-layer tests for merge-rule behavior (including conflict cases).
  - Ensure no regression in existing 156-test suite.

- [x] Verify and document
  - Run `swift test`.
  - Run `bash scripts/build_local_app.sh`.
  - Add review notes to this todo file.
  - Update `progress.txt` equivalent status file if present; if missing, log this gap and next-step recommendation.

## REVIEW

- Implemented `v3_log_sync_state` migration and typed accessors in `WorkoutDatabase`.
- Added row-level session log query API for reconciliation reads.
- Added `LiveAppGateway+BidirectionalSync.swift` with deterministic reconciliation rules:
  - one-sided change syncs to opposite side
  - two-sided identical accepted unchanged
  - two-sided divergent conflicts resolved deterministically (sheet-preferred when both non-empty)
- Wired reconciliation into `loadPlanSnapshot(forceRemote: true)` only.
- Added Settings UI surface for manual sync and status visibility.
- Added tests:
  - persistence tests for `log_sync_state` and session-log row fetch
  - resolver rule tests in desktop app tests
  - coordinator test for manual sync action status update
- Verification:
  - `swift test` passed: 162 tests, 3 skipped, 0 failures.
  - `bash scripts/build_local_app.sh` passed after clearing xattrs on `dist/SamsWorkoutNative.app`.
  - Live check passed: `RUN_LIVE_E2E=1 swift test --filter WorkoutDesktopAppLiveE2ETests/testLiveWeeklySheetNamesContainNo2099Tabs`.
- `progress.txt` is not present in workspace root (doc gap). Recommendation: create canonical `progress.txt` in project root to carry phase/status state between sessions.
