# Sam's Workout Native — Backend + DB Brief (for Claude)

## 1. What This App Does

This is a native macOS Swift app that helps one athlete run a weekly training workflow end to end:

- Generates a full weekly plan from trainer-provided Fort workouts (Mon/Wed/Fri) plus constraints.
- Writes the plan to local markdown and Google Sheets.
- Uses Google Sheets as source of truth for weekly plans/logs.
- Keeps a local GRDB/SQLite cache for fast analytics and history.
- Provides analytics views (progress, weekly review, exercise history, DB status).
- Supports InBody scan tracking in local DB.

## 2. Runtime + Architecture

- Runtime: Swift package (`native/SamsWorkoutNative`)
- App layer: `WorkoutDesktopApp`
- Integrations layer: `WorkoutIntegrations` (Anthropic + Google Sheets + auth)
- Persistence layer: `WorkoutPersistence` (GRDB)
- Domain rules: `WorkoutCore`

Main gateway:
- `LiveAppGateway` orchestrates generation, Sheets I/O, DB rebuild/sync, and analytics reads.

## 3. Core Backend Flows

### A) Plan Generation

1. User enters Fort text for Monday/Wednesday/Friday.
2. Gateway builds prompt/context and calls Anthropic.
3. Deterministic repairs + validation/correction loop run.
4. Final plan is saved locally and (normally) written to Google Sheets weekly tab.

### B) Plan Viewing + Sync

- Local-first view by default.
- `forceRemote` fetch reads latest preferred weekly tab from Sheets.
- On forced remote load, app now runs **bidirectional log reconciliation** between Sheets column H and local DB before rendering snapshot.

### C) DB Cache Rebuild

- Rebuild imports all weekly sheet tabs (`A:H`) into temp DB, then atomically swaps.
- Preserves local-only InBody scans.

### D) Analytics

Reads from local DB cache for speed:
- progress summary
- weekly review summaries
- top exercises
- recent sessions
- weekly volume
- weekly average RPE
- muscle group volumes
- per-exercise history

## 4. Database Model (Current)

Main tables:
- `exercises`
- `workout_sessions`
- `exercise_logs`
- `exercise_aliases`
- `inbody_scans`
- `log_sync_state` (new)

Important constraints:
- `workout_sessions` unique (`sheet_name`, `day_label`)
- `exercise_logs` unique (`session_id`, `source_row`)
- `log_sync_state` unique (`sheet_name`, `day_label`, `source_row`)

## 5. New Bidirectional Sync Capability (Added)

Purpose:
- Reconcile diverged logs across Google Sheets and local DB.

Input key:
- `(sheetName, dayLabel, sourceRow)`

Sync state persisted per row:
- `last_synced_sheet_log`
- `last_synced_db_log`
- `last_resolution`

Deterministic merge rules:
- Only sheet changed -> pull to DB
- Only DB changed -> push to Sheets
- Both changed and identical -> unchanged
- Both changed and different -> conflict; deterministic tie-break (currently sheet-preferred when both non-empty)

UI surface:
- Settings > Database > **Run Sync Now**
- Shows last sync timestamp + summary counters (pulled/pushed/conflicts/unchanged)

## 6. Current API Interaction Pattern

### Anthropic
- Primarily single large generation call with streamed response.
- Context includes Fort compilation + DB-derived context + constraints.

### Google Sheets
- HTTP calls for metadata, read `A:H`, batch update log cells, sheet clear/write/archive.

## 7. What Should Improve Next (Backend/DB)

High-value targets:

1. **Sync audit trail + replayability**
- Add append-only sync event table with timestamps and per-row diffs.
- Enables postmortems and deterministic replays.

2. **Conflict policy configurability**
- Move tie-break from hardcoded to policy enum (sheet-preferred / db-preferred / non-empty-preferred).

3. **Incremental sync scheduler**
- Track dirty sessions and sync in small batches instead of full forced pass.

4. **Stronger idempotency + retry semantics**
- Job IDs and retry-safe writes for partial network failure cases.

5. **Targeted context retrieval for generation**
- Pull only relevant logs by normalized exercise + recency windows, with strict token budget.

## 8. “Conversational” API Calls Without More Total Tokens

Short answer: **Yes, more API calls can improve quality if each call is smaller and purpose-specific, and total tokens are budgeted globally.**

Use a staged pipeline instead of one giant prompt:

1. **Call 1: Intent + constraints extraction (cheap)**
- Input: Fort text + directives only
- Output: compact structured plan requirements JSON

2. **Call 2: Retrieval selector (cheap)**
- Input: requirements JSON + compact catalog stats
- Output: exact DB context keys needed

3. **Call 3: Final synthesis (main call)**
- Input: requirements + only selected history rows
- Output: final weekly plan

Why this can be better at same token budget:
- Reduces irrelevant context in the expensive final call.
- Improves adherence via explicit intermediate structure.
- Keeps failures local (you can retry one step, not whole run).

Guardrail:
- Enforce per-run token budget accounting across all calls.
- If step 1/2 cost grows, cut context size automatically for step 3.

## 9. Operational Notes

- Tests are strong and should stay green (`swift test`).
- Live integration tests are opt-in (`RUN_LIVE_E2E=1`).
- OAuth token refresh path is critical for Sheets reliability.
- Keep Sheets schema fixed to 8 columns (`A:H`) to avoid parser/sync regressions.

## 10. Suggested First Claude Task

Implement a **token-budgeted staged generation pipeline** behind a feature flag:
- Keep current path as fallback.
- Add per-stage token telemetry.
- Compare output quality + total token usage over 20 real runs.
