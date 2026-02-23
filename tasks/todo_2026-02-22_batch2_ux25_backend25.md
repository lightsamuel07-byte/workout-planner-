# Batch Plan: Native App Improvements (UX 25 + Backend 25) - Batch 2

Date: 2026-02-22
Scope: `/Users/samuellight/Desktop/Sam's Workout App/native/SamsWorkoutNative`

## Objectives
- Ship second production-safe batch with 25 UX and 25 backend improvements.
- Preserve `2099` protections and live E2E integrity.
- Keep local app signed and shippable after batch.

## Traceability
- PRD FR-001/FR-002/FR-003/FR-005/FR-006/FR-008/FR-011
- APP_FLOW sections 1, 2, 3.2, 3.3, 3.4, 3.8
- DESIGN_SYSTEM / FRONTEND_GUIDELINES consistency and readability

## Plan

### A) Backend Improvements (25)
- [x] B2-01 Add setup checklist model.
- [x] B2-02 Add setup checklist computation.
- [x] B2-03 Add setup completion percent helper.
- [x] B2-04 Add setup missing-summary helper.
- [x] B2-05 Add generation readiness severity helper.
- [x] B2-06 Add generation duplication boolean helper.
- [x] B2-07 Add generation issue count helper.
- [x] B2-08 Add generation stable fingerprint helper.
- [x] B2-09 Add logger search query state.
- [x] B2-10 Add logger search filtering logic.
- [x] B2-11 Add logger visible count helper.
- [x] B2-12 Add logger pending visible count helper.
- [x] B2-13 Add logger edited count helper.
- [x] B2-14 Add logger notes count helper.
- [x] B2-15 Add logger block progress model + helper.
- [x] B2-16 Add plan day ordering helper by weekday.
- [x] B2-17 Add ordered plan day list helper.
- [x] B2-18 Update selected plan day resolution to ordered list.
- [x] B2-19 Update adjacent day navigation to ordered list.
- [x] B2-20 Add selected day position helper.
- [x] B2-21 Add history empty reason helper.
- [x] B2-22 Add db weekday completion percent helper.
- [x] B2-23 Add formatted rebuild-summary line helper.
- [x] B2-24 Add analytics freshness helper text.
- [x] B2-25 Add regression tests for new helper/filter logic.

### B) UX Improvements (25)
- [x] U2-01 Setup checklist visual with checkmarks.
- [x] U2-02 Setup completion progress bar.
- [x] U2-03 Setup missing-summary caption.
- [x] U2-04 Setup paste-auth-hint-from-clipboard action.
- [x] U2-05 Setup clear-sensitive-fields action.
- [x] U2-06 Dashboard status headline row.
- [x] U2-07 Dashboard logger pending metric card.
- [x] U2-08 Dashboard logger edited metric card.
- [x] U2-09 Dashboard analytics freshness caption.
- [x] U2-10 Generate readiness severity tint.
- [x] U2-11 Generate duplicate warning card.
- [x] U2-12 Generate issue count chip.
- [x] U2-13 Generate fingerprint display.
- [x] U2-14 Generate copy-all-inputs action.
- [x] U2-15 View Plan ordered day picker source.
- [x] U2-16 View Plan day position caption.
- [x] U2-17 Logger search field.
- [x] U2-18 Logger visible/pending counters.
- [x] U2-19 Logger block-progress section.
- [x] U2-20 Logger completed-row background styling.
- [x] U2-21 Weekly Review best/worst sheet caption.
- [x] U2-22 Exercise History quick suggestions row.
- [x] U2-23 Exercise History empty reason caption.
- [x] U2-24 DB Status weekday completion percentages.
- [x] U2-25 DB Status formatted rebuild summary bullets.

### C) Validation
- [x] Run `swift test --filter WorkoutDesktopAppTests`.
- [x] Run `swift test --filter WorkoutPersistenceTests`.
- [x] Run `swift test` full package.
- [x] Run `RUN_LIVE_E2E=1 swift test --filter WorkoutDesktopAppLiveE2ETests`.
- [x] Run `./scripts/build_local_app.sh`.
- [x] Update `progress.txt` with Batch 2 results.

## Review Notes
- Batch 2 shipped with all planned `25 UX + 25 backend` items completed.
- Validation summary:
  - `swift test --filter WorkoutDesktopAppTests --disable-index-store` passed.
  - `swift test --filter WorkoutPersistenceTests --disable-index-store` passed.
  - `swift test --disable-index-store` passed (`125` tests, `3` skipped, `0` failures).
  - `RUN_LIVE_E2E=1 swift test --filter WorkoutDesktopAppLiveE2ETests --disable-index-store` passed:
    - `testLiveGenerateWriteLogAndSync` `55.051s`
    - `testLiveRebuildImportsPriorHistoryFromSheets` `5.009s`
    - `testLiveWeeklySheetNamesContainNo2099Tabs` `0.330s`
  - `./scripts/build_local_app.sh` passed; signed app rebuilt at
    `/Users/samuellight/Desktop/Sam's Workout App/native/SamsWorkoutNative/dist/SamsWorkoutNative.app`.
- One transient SwiftPM race (`runner.swift was modified during the build`) occurred once and resolved on immediate rerun.
