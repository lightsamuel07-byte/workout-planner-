# Batch Plan: Native App Improvements (UX 25 + Backend 25)

Date: 2026-02-22
Scope: `/Users/samuellight/Desktop/Sam's Workout App/native/SamsWorkoutNative`

## Objectives
- Ship one production-safe batch with 25 UX improvements and 25 backend improvements.
- Keep app buildable and testable at every step.
- Hard-stop the `2099` tab regression path with runtime guard + test coverage.

## Traceability
- PRD FR-003/FR-004/FR-005/FR-006/FR-007/FR-011
- APP_FLOW sections 3.2, 3.3, 3.4, 3.8
- DESIGN_SYSTEM and FRONTEND_GUIDELINES token + responsiveness constraints
- BACKEND_STRUCTURE flows A/B/C and auth constraints

## Plan

### A) 2099 Guard Hardening
- [x] Add runtime weekly-sheet date sanitization guard in `LiveAppGateway` so generation never emits far-future years.
- [x] Add deterministic unit tests for sanitized sheet naming.
- [x] Keep live guard test asserting no weekly plan tabs containing year `2099`.

### B) Backend Improvements (25)
- [x] B01 Add `GenerationReadinessReport` model for deterministic preflight checks.
- [x] B02 Add preflight check: missing day inputs list.
- [x] B03 Add preflight check: day header presence (`MONDAY/WEDNESDAY/FRIDAY`).
- [x] B04 Add preflight check: minimum non-empty lines per day.
- [x] B05 Add preflight check: duplicate-day text detection.
- [x] B06 Add `generationReadinessSummary` computed output.
- [x] B07 Add explicit `generationDisabledReason` string for UI.
- [x] B08 Add explicit `loggerSaveDisabledReason` string for UI.
- [x] B09 Add explicit `dbRebuildDisabledReason` string for UI.
- [x] B10 Add `loggerCompletionPercent` computed metric.
- [x] B11 Add `weeklyReviewAverageCompletion` computed metric.
- [x] B12 Add `weeklyReviewBestWeek` helper.
- [x] B13 Add `weeklyReviewWorstWeek` helper.
- [x] B14 Add `planDayCompletionCount` helper (rows with logs).
- [x] B15 Add `planDayCompletionPercent` helper.
- [x] B16 Add `planDayHasLogs` helper.
- [x] B17 Add `planVisibleExerciseCount` helper.
- [x] B18 Add `planBlockCatalog` helper.
- [x] B19 Add plan block filter state and filtering logic.
- [x] B20 Add plan show-only-logged toggle state and filtering logic.
- [x] B21 Add logger block filter state and filtering logic.
- [x] B22 Add logger row-level completion helper for deterministic styling.
- [x] B23 Add robust numeric parser that handles comma decimals for volume estimation.
- [x] B24 Add normalized status classification for auth/retry guidance.
- [x] B25 Add tests for new coordinator filter/readiness metrics.

### C) UX Improvements (25)
- [x] U01 Setup: readiness badge with severity.
- [x] U02 Setup: compact quick-help panel for token/auth expectations.
- [x] U03 Setup: copy auth hint button.
- [x] U04 Unlock: inline clear error feedback when typing.
- [x] U05 Dashboard: compact health strip with completion + invalid counters.
- [x] U06 Dashboard: last-refresh chips grouped into one section.
- [x] U07 Dashboard: quick action toolbar grouping.
- [x] U08 Generate: preflight checklist card.
- [x] U09 Generate: disabled-reason text under Generate button.
- [x] U10 Generate: normalize-input action button.
- [x] U11 Generate: line-count indicators per day input.
- [x] U12 Generate: visual status when inputs look duplicated.
- [x] U13 View Plan: block filter picker.
- [x] U14 View Plan: show-only-logged toggle.
- [x] U15 View Plan: completion metrics card (logged/visible rows).
- [x] U16 View Plan: empty-filter state with reset hint.
- [x] U17 Logger: block filter picker.
- [x] U18 Logger: save-disabled reason text.
- [x] U19 Logger: completion progress bar.
- [x] U20 Logger: row completion icon in each exercise row.
- [x] U21 Weekly Review: summary cards (avg/best/worst completion).
- [x] U22 Exercise History: selected exercise summary row (latest/max/delta/date).
- [x] U23 DB Status: rebuild-disabled reason text.
- [x] U24 DB Status: rebuild summary readability improvements.
- [x] U25 Global: consistent section spacing and small helper captions.

### D) Validation
- [x] Run `swift test --filter WorkoutDesktopAppTests`.
- [x] Run `swift test --filter WorkoutPersistenceTests`.
- [x] Run `swift test` full package.
- [x] Run live suite: `RUN_LIVE_E2E=1 swift test --filter WorkoutDesktopAppLiveE2ETests`.
- [x] Update `progress.txt` with shipped batch details.

## Review Notes (to fill after implementation)
- Batch shipped successfully.
- All targeted items implemented in app layer (`AppModels`, `AppCoordinator`, `AppViews`, `LiveAppGateway`) with regression coverage.
- Validation complete:
  - `swift test --filter WorkoutDesktopAppTests` passed.
  - `swift test --filter WorkoutPersistenceTests` passed.
  - `swift test` full suite passed.
  - `RUN_LIVE_E2E=1 swift test --filter WorkoutDesktopAppLiveE2ETests` passed.
  - `./scripts/build_local_app.sh` passed and app re-signed.
