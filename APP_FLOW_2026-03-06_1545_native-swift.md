# APP_FLOW (Native Swift Track)

Last updated: 2026-03-06
Supersedes for active runtime: `APP_FLOW.md`
Runtime scope: `native/SamsWorkoutNative`

## 1. Entry Flow

1. User launches the native macOS app.
2. App loads local config from App Support.
3. If setup is incomplete, the app shows the Setup flow.
4. If setup is complete, the app restores route state and loads the main `NavigationSplitView`.
5. On launch, the coordinator refreshes the current plan and starts a background DB rebuild.

## 2. Setup Flow

1. User enters Anthropic API key.
2. User enters Google Spreadsheet ID.
3. User enters Google auth hint / token path.
4. App validates required fields and persists config locally.
5. Successful setup unlocks the main routes.

## 3. Global Navigation Model

Routes:

- Dashboard
- Generate Plan
- View Plan
- Progress
- Weekly Review
- Exercise History
- Settings

The coordinator owns route selection and shared runtime state.

## 4. Page-Level Flows

### 4.1 Dashboard

- Shows this week summary and quick actions.
- Displays 1RM coverage, recent sessions, and high-level readiness/status surfaces.

### 4.2 Generate Plan

1. User pastes Monday / Wednesday / Friday Fort inputs.
2. User chooses new-cycle vs continuing-cycle behavior.
3. App runs preflight checks.
4. App executes staged generation:
   - Fort normalization
   - exercise selection
   - athlete-state distillation
   - plan synthesis
   - deterministic repairs
   - validation / correction loop
5. App saves the plan locally and writes it to Google Sheets.
6. App reports validation, fidelity, and pipeline status to the user.

### 4.3 View Plan

- Loads plan snapshot from local files first.
- `forceRemote` refresh loads from Google Sheets.
- Remote refresh also triggers bidirectional Sheets-DB log reconciliation before the snapshot is parsed.
- User can filter by block, search exercises, and show/hide notes and logs.

### 4.4 Progress

- Renders body-composition data, weekly volume, weekly RPE, block volume, and top exercises.
- Reads from GRDB-backed analytics queries and persisted InBody scans.

### 4.5 Weekly Review

- Shows week-level summaries and completion metrics.
- Supports browsing historical week rows from the DB cache.

### 4.6 Exercise History

- Loads a catalog from the local DB.
- Supports search/suggestion and per-exercise load/history display.

### 4.7 Settings

- 1RM entry and persistence
- Fort section override management
- Database rebuild action
- Bidirectional sync action
- Bidirectional sync conflict policy selection
- Sync audit visibility
- App credential status

## 5. Maintenance / Recovery Flows

### 5.1 Rebuild DB Cache

1. User triggers rebuild in Settings.
2. App imports historical sheet data into GRDB.
3. App refreshes analytics and status text.

### 5.2 Bidirectional Sync

1. User triggers sync in Settings or indirectly via remote plan refresh.
2. App compares Google Sheets logs against local DB logs and row-level sync checkpoints.
3. App resolves differences using the configured conflict policy.
4. App writes required pulls/pushes.
5. App persists new sync checkpoints and audit events.
6. App updates status summary and refreshes analytics.

## 6. Failure Paths

- Missing setup values: block app runtime and show explicit checklist gaps.
- Google auth failure: show actionable error from the underlying integration layer.
- Remote read/write failure: preserve current local state and surface failure text.
- Validation failure during generation: keep the correction loop running until success or surfaced failure.
