# BACKEND_STRUCTURE (Native Swift Addendum - Sync Review and Progression)

Last updated: 2026-03-06
Runtime scope: `native/SamsWorkoutNative`
Addendum to active native docs:
- `BACKEND_STRUCTURE_2026-03-06_1545_native-swift.md`

## 1. Generate Flow Addendum

### Flow A1: Hardened Stage 1 Exercise Selection

1. Gateway sends a low-token supplemental exercise-selection request.
2. Gateway parses the selection into Tuesday / Thursday / Saturday exercise lists.
3. Gateway validates:
   - required days present
   - minimum day exercise count
   - no cross-day duplicate exercises
4. If invalid, gateway sends one compact corrective follow-up request.
5. Gateway records telemetry for both the initial Stage 1 call and the correction call if used.
6. Gateway proceeds with either corrected targeted context or generic DB fallback.

## 2. Sync Flow Addendum

### Flow D1: Manual Conflict Repair

1. Coordinator passes a selected conflict audit event and chosen side to the gateway.
2. Gateway loads the target row context for that sheet/day/source-row.
3. Gateway writes the chosen log value to Google Sheets column `H`.
4. Gateway writes the same chosen log value through the local sync import path to the DB.
5. Gateway upserts `log_sync_state` for the repaired row.
6. Gateway appends a new `sync_audit_events` row describing the manual repair.
7. Coordinator refreshes sync audit output and summary text.

## 3. Progression Flow Addendum

### Flow E: Progression Insight Derivation

1. Gateway requests recent progression-candidate history from the local DB.
2. A deterministic progression engine derives structured insights per exercise using first-pass RPE thresholds:
   - `PROGRESS` at latest RPE `<= 7.0` with at least 2 sessions
   - `LOCK` at latest RPE `>= 8.5`
   - `NEUTRAL` otherwise
3. The Progress page consumes those insights directly.
4. The generation pipeline continues to consume structured progression recommendations instead of raw log text alone.

## 4. Persistence Impact

- No new external service is added.
- Existing tables remain the storage foundation:
  - `exercise_logs`
  - `log_sync_state`
  - `sync_audit_events`
- Manual repair uses existing audit and sync-state persistence, with additional audit event rows to distinguish manual repairs from automatic sync resolution.
