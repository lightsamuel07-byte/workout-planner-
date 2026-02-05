# APP_FLOW

Last updated: 2026-02-05

## 1. Entry Flow

1. User launches app (`streamlit run app.py`).
2. App renders password gate.
3. On valid password, app initializes session state and loads sidebar navigation.
4. Default route: `dashboard`.

## 2. Global Navigation Model

Sidebar sections and routes:
- THIS WEEK
  - Dashboard (`dashboard`)
  - Log Workout (`log_workout`)
  - View Plan (`plans`)
- PLANNING
  - Generate Plan (`generate`)
- ANALYTICS
  - Progress (`progress`)
  - Weekly Review (`weekly_review`)
  - Exercise History (`exercise_history`)
  - DB Status (`database_status`)

Shared route state:
- `st.session_state.current_page`

## 3. Page-Level Flows

### 3.1 Dashboard
- Loads current week dates.
- Pulls latest local plan and most recent weekly sheet name.
- If no plan exists, shows empty state and CTA to generate.
- Shows week cards (Mon-Sun), summary stats, quick actions, and recent activity.

### 3.2 Generate Plan
1. User pastes Fort workouts (Mon/Wed/Fri).
2. User selects new vs continuing program.
3. If continuing, user optionally selects prior weekly sheet.
4. User clicks Generate.
5. App loads config/secrets, builds generation context, calls Claude.
6. App saves markdown (+ optional explanation), archives prior artifacts, writes new sheet tab.
7. App confirms success and offers navigation actions.

Empty/error paths:
- Missing API key -> blocking error.
- Missing required workout text -> generate disabled.
- Sheets read/write errors -> surfaced with warnings/errors.

### 3.3 View Plans
- Primary source: local `output/workout_plan_*.md` files.
- Fallback source: Google Sheets weekly plan tabs.
- User selects plan and day, then views normalized exercise cards.
- Optional explanation markdown shown for local plan if present.

### 3.4 Log Workout
1. Resolve most recent weekly sheet.
2. Parse sheet and match today's day label.
3. Render block-grouped exercise cards with logging controls.
4. User enters performance + optional RPE + optional notes.
5. Save writes logs to Google Sheets column H.
6. Successful save triggers local SQLite sync.

Alternative states:
- No plan sheets -> prompt to generate plan.
- No workout for current day -> rest-day state.
- Save failure -> troubleshooting guidance.

### 3.5 Progress
- Loads recent historical data from Sheets.
- Shows progression metrics for squat/bench/deadlift when available.
- Shows weekly volume chart and muscle group summaries.

### 3.6 Weekly Review
- User selects any weekly sheet.
- App renders week summary metrics and day-by-day expanders.
- Includes week-over-week volume/completion comparison when previous week exists.

### 3.7 Exercise History
- Loads historical exercises.
- User filters/searches exercise names.
- Shows per-exercise session timeline with progression and logging details.

### 3.8 DB Status
- If DB file missing: show bootstrap action to import from Sheets.
- If DB exists: show counts, recent sessions, top exercises, RPE trend.

## 4. Data Flow Summary

1. Plan generation:
   - UI input -> prompt build -> Claude -> local markdown + Google Sheets write.

2. Workout logging:
   - Google Sheets read -> UI logging input -> Google Sheets write -> SQLite sync.

3. Analytics/review:
   - Google Sheets history read (and SQLite for DB status context) -> derived metrics -> UI.

## 5. Route Notes

- `pages/diagnostics.py` exists but is not linked in current sidebar routing.
- `pages/workout_logger_minimal.py` exists as a test page and is not routed.
