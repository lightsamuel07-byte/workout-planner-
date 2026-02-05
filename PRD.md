# PRD

Last updated: 2026-02-05
Product: Samuel's Workout Planner

## 1. Product Summary

Samuel's Workout Planner is a Streamlit application and companion CLI that:
- converts trainer-provided Fort workouts (Mon/Wed/Fri) into a weekly plan,
- generates supplemental sessions (Tue/Thu/Sat) with Claude,
- writes plans to Google Sheets,
- supports daily workout logging,
- syncs logs into local SQLite for longitudinal analysis.

## 2. Primary User

- Single primary athlete workflow (Samuel).
- Uses desktop for planning/review and mobile in-gym logging.

## 3. Product Goals

1. Generate weekly plans quickly with strict training constraints.
2. Make daily logging fast and reliable.
3. Keep data available in both Google Sheets and local SQLite.
4. Provide clear progress visibility across weeks.

## 4. Non-Goals

- No backend web service/API layer.
- No multi-user account system.
- No feature-level editing of trainer programming logic outside documented config/rules.

## 5. Functional Requirements

### FR-001 Access Control
- The web app must require password entry before navigation (`APP_PASSWORD` in Streamlit secrets).
- If password secret is missing, app must block usage and show setup guidance.

### FR-002 Navigation Shell
- App must provide grouped sidebar navigation:
  - THIS WEEK: Dashboard, Log Workout, View Plan
  - PLANNING: Generate Plan
  - ANALYTICS: Progress, Weekly Review, Exercise History, DB Status
- Current page must be stored in session state and rerender on selection.

### FR-003 Generate Plan Workflow
- User must paste Monday/Wednesday/Friday Fort workouts.
- User must choose whether week is new program vs continuing.
- For continuing programs, user can select prior week sheet for progression context.
- App must call Claude to generate a complete weekly plan.
- Plan output must be saved to local markdown and written to Google Sheets.

### FR-004 Plan Persistence
- App must archive existing same-week local markdown plan before overwrite.
- App must archive existing same-week Google sheet tab before writing replacement.
- Explanation output should be saved as a companion markdown file when available.

### FR-005 View Plans
- App must display local markdown plans when available.
- If no local markdown exists, app must fall back to Google Sheets weekly plans.
- User must be able to view day-level exercise details (sets/reps/load/rest/notes).

### FR-006 Workout Logger
- App must load the most recent weekly plan sheet and resolve today's workout.
- User must be able to log performance, optional RPE, and optional notes per exercise.
- Quick logging actions must include Done and Skip.
- Save action must write logs into Google Sheets column H.

### FR-007 Local DB Sync
- On successful sheet save, app must sync non-empty logs into local SQLite.
- DB schema must maintain normalized exercise names, sessions, and exercise logs.
- Session date inference must support both explicit day-date labels and sheet anchor date parsing.

### FR-008 Progress Analytics
- App must compute and display:
  - main lift progression,
  - weekly volume,
  - completion rate,
  - muscle-group volume trends,
  - biceps grip rotation compliance.

### FR-009 Weekly Review
- App must allow week-by-week browsing of historical sheets.
- App must provide weekly summary metrics and day-by-day breakdown.

### FR-010 Exercise History
- App must allow exercise search and selection.
- App must show session history, load trend, and parsed RPE where available.

### FR-011 Database Status
- App must show local SQLite health metrics and recent session summaries.
- If DB does not exist, app must allow one-click bootstrap import from Sheets.

### FR-012 CLI Parity
- `main.py` must support end-to-end plan generation flow via terminal:
  1. config load,
  2. auth,
  3. trainer workout input,
  4. plan generation,
  5. local save,
  6. Google Sheets write.

## 6. Non-Functional Requirements

### NFR-001 Mobile-First Usability
- Primary controls must be touch-friendly (44px+, with 48px for key mobile controls).
- Layout must degrade cleanly at tablet and phone widths.

### NFR-002 Visual Consistency
- Shared tokens and component styles must come from `src/design_system.py` and `assets/styles.css`.

### NFR-003 Reliability and Fallbacks
- App must degrade gracefully when data or auth is unavailable (empty states + actionable messaging).

### NFR-004 Security and Secrets
- API keys and app password must not be hardcoded.
- Secrets must come from environment variables or Streamlit secrets.

### NFR-005 Data Safety
- Existing plan artifacts must be archived before replacement.
- Logging should prioritize preserving captured data over destructive rewrite behavior.

## 7. Traceability to Current Code

- App shell + auth: `app.py`
- Page flows: `pages/*.py`
- UI primitives: `src/ui_utils.py`, `src/design_system.py`, `assets/styles.css`
- AI generation: `src/plan_generator.py`
- Sheet IO: `src/sheets_reader.py`, `src/sheets_writer.py`
- DB persistence: `src/workout_db.py`, `src/workout_sync.py`, `scripts/import_google_sheets_history.py`
- Analytics: `src/analytics.py`, `src/generation_context.py`
