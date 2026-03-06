# APP_FLOW (Native Swift Addendum - Sync Review and Progression)

Last updated: 2026-03-06
Runtime scope: `native/SamsWorkoutNative`
Addendum to active native docs:
- `APP_FLOW_2026-03-06_1545_native-swift.md`

## 1. Generate Plan Addendum

### 1.1 Stage 1 Exercise Selection Validation

1. App sends the low-token Stage 1 exercise-selection request.
2. App parses the returned Tuesday / Thursday / Saturday lists.
3. App validates the parsed selection locally.
4. If valid, generation continues into targeted DB context distillation.
5. If invalid, app sends one compact correction request containing:
   - the malformed Stage 1 output
   - the deterministic issue list
   - the minimal hard rules needed to repair the selection
6. If the correction result is still invalid, app falls back to generic DB context and continues the rest of generation.

### 1.2 Post-Run Telemetry

- After generation completes, the Generate Plan page shows pipeline telemetry beneath the live generation panel.
- The telemetry section is read-only and reflects the last completed generation run.

## 2. Settings Addendum - Conflict Review and Repair

### 2.1 Conflict Review

1. User opens Settings.
2. App shows recent sync audit rows, prioritizing conflict rows.
3. For each conflict row, the app shows both original sides and the prior automatic resolution.

### 2.2 Manual Repair

1. User chooses either `Apply Google Sheets Value` or `Apply Local DB Value`.
2. App replays that chosen value to both stores for the targeted row.
3. App updates row-level sync checkpoint state.
4. App writes a new sync audit event for the manual repair.
5. App refreshes sync audit output and status text inline.

## 3. Progress Addendum - Progression Insights

1. User opens Progress.
2. App loads recent progression insights derived from local DB history.
3. App shows signal, reason, last prescription, and recommendation for each insight.
4. User can use this surface as a review/debug layer for why the generator is recommending progression or a hold.
