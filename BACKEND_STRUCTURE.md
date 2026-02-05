# BACKEND_STRUCTURE

Last updated: 2026-02-05

## 1. Backend Topology

This project uses an in-process Python backend architecture (no separate web API service):

- External services:
  - Anthropic Claude API
  - Google Sheets API

- Local persistence:
  - SQLite (`data/workout_history.db`)
  - Markdown plan artifacts (`output/*.md`)

- Core backend modules (`src/`):
  - `plan_generator.py`
  - `sheets_reader.py`
  - `sheets_writer.py`
  - `workout_db.py`
  - `workout_sync.py`
  - `generation_context.py`
  - `analytics.py`

## 2. Module Responsibilities

### `src/plan_generator.py`
- Builds compressed generation prompt with hard training constraints.
- Calls Anthropic messages API.
- Post-processes output (exercise swaps, even DB load enforcement, range validation/correction).
- Generates explanation bullets.
- Saves plan files when invoked from CLI flow.

### `src/sheets_reader.py`
- Handles Google auth for local/cloud/headless contexts.
- Reads weekly sheet rows (A:H schema).
- Parses day/exercise structure for UI and analytics.
- Retrieves all weekly plan sheet names.
- Writes workout logs to column H for matched exercises.

### `src/sheets_writer.py`
- Parses markdown plan format into row data.
- Ensures destination sheet exists.
- Optionally archives existing sheet tab.
- Clears and rewrites sheet content in one workflow.

### `src/workout_db.py`
- Defines SQLite schema and upsert operations:
  - `exercises`
  - `workout_sessions`
  - `exercise_logs`
- Enforces normalized exercise identity and session uniqueness.

### `src/workout_sync.py`
- Converts logger entries into DB upserts.
- Infers session dates from day labels and sheet anchors.
- Extracts/coerces RPE values from explicit fields or log text.

### `src/generation_context.py`
- Builds compact DB-derived context for plan generation.
- Targets prior supplemental exercises and recent log entries.

### `src/analytics.py`
- Aggregates historical sheet data for:
  - main lift progression,
  - weekly volume,
  - completion rate,
  - grip rotation compliance,
  - muscle group volume summaries.

## 3. End-to-End Data Flows

### Flow A: Generate Weekly Plan
1. UI/CLI collects trainer workouts and preferences.
2. Reader pulls optional prior context from Sheets.
3. Optional DB context is generated from SQLite.
4. `PlanGenerator.generate_plan()` calls Claude.
5. Plan is saved locally and written to Google Sheets via writer.

### Flow B: Log Workout
1. Logger reads most recent weekly sheet and today's exercises.
2. User logs performance/RPE/notes.
3. Reader writes logs into Google Sheets column H.
4. Sync layer upserts non-empty logs into SQLite.

### Flow C: Analytics and Review
1. Pages load historical sheet data through reader.
2. Analytics module computes trends and summary metrics.
3. DB Status page reads SQLite directly for health and coverage views.

## 4. SQLite Schema (Current)

### Table: `exercises`
- `id` (PK)
- `name`
- `normalized_name` (unique)
- timestamps

### Table: `workout_sessions`
- `id` (PK)
- `sheet_name`
- `day_label`
- `day_name`
- `session_date`
- `source`
- timestamps
- unique constraint on (`sheet_name`, `day_label`)

### Table: `exercise_logs`
- `id` (PK)
- `session_id` (FK)
- `exercise_id` (FK)
- prescribed fields (`sets/reps/load/rest/notes`)
- `log_text`
- `parsed_rpe`
- `parsed_notes`
- `source_row`
- `source`
- timestamps
- unique constraint on (`session_id`, `source_row`)

## 5. Auth Strategy

Google Sheets auth priority path:
1. Streamlit Cloud service account secret (`gcp_service_account`)
2. Service account file arg/env
3. Service account JSON env
4. Local OAuth token flow (`credentials.json` + `token.json`)

Anthropic auth:
- `ANTHROPIC_API_KEY` from Streamlit secrets or environment.

## 6. Operational Scripts

- Historical DB import: `scripts/import_google_sheets_history.py`
  - Imports all weekly sheets or a selected subset into SQLite.
  - Supports dry-run and configurable DB path.

## 7. Known Constraints

- Backend is tightly coupled to current markdown plan format and sheet schema.
- Weekly plan naming patterns are parsed by regex and must remain compatible.
- Large parts of analytics rely on parseable numeric strings in set/rep/load fields.
