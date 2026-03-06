# PRD (Native Swift Track)

Last updated: 2026-03-06
Supersedes for active runtime: `PRD.md`
Runtime scope: `native/SamsWorkoutNative`

## 1. Product Summary

Samuel's Workout Planner is now a native macOS Swift app for a single athlete workflow. It:

- generates a six-day weekly plan from Fort inputs and local history,
- writes and archives plans in Google Sheets,
- caches training history in a local SQLite database via GRDB,
- surfaces analytics, weekly review, exercise history, and body-composition tracking,
- reconciles workout logs between Google Sheets and the local DB.

There is no separate backend service. All integrations run in-process inside the native app.

## 2. Primary User

- Single primary athlete workflow (Samuel).
- Desktop-first usage on macOS native app.

## 3. Product Goals

1. Generate weekly plans with deterministic training constraints and minimal manual cleanup.
2. Keep Google Sheets and the local DB aligned without silent data loss.
3. Make progress, weekly review, and exercise history immediately available from local cache.
4. Keep setup, recovery, and maintenance workflows inside the native app.

## 4. Non-Goals

- No multi-user support.
- No backend web API or remote server process.
- No App Store distribution in the current track.
- No undocumented training-rule changes.

## 5. Functional Requirements

### FR-001 Setup and Credentials

- The app must gate runtime features behind a local setup flow.
- The user must be able to store:
  - Anthropic API key
  - Google Spreadsheet ID
  - Google auth hint / token location
- Setup values must persist locally and restore on launch.

### FR-002 Navigation Shell

- The app must provide native route parity for:
  - Dashboard
  - Generate Plan
  - View Plan
  - Progress
  - Weekly Review
  - Exercise History
  - Settings

### FR-003 Plan Generation

- The user must be able to provide Monday / Wednesday / Friday Fort inputs.
- The app must support new-cycle and continuing-cycle generation flows.
- Generation must preserve hard training constraints from the domain layer.
- The generation pipeline must support staged prompting:
  - Fort normalization
  - supplemental exercise selection
  - athlete-state distillation from DB history
  - plan synthesis
  - deterministic repairs and validation
- Plan generation must report progress to the UI and preserve failure visibility.

### FR-004 Plan Persistence and Sheet Writes

- Generated plans must be saved locally.
- Existing same-week local plan files must be archived before overwrite.
- Existing same-week Google Sheets tabs must be archived before replacement.
- The app must preserve the canonical 8-column Google Sheets schema (`A:H`).

### FR-005 Plan Viewing

- The app must load local plan snapshots first when available.
- If local files are unavailable or remote refresh is requested, the app must fall back to Google Sheets.
- The user must be able to browse day-level exercise rows, notes, and logs.

### FR-006 Analytics and Review

- The app must provide:
  - progress summary
  - weekly review summaries
  - weekly volume trend
  - weekly RPE trend
  - muscle-group volume breakdown
  - top exercises
  - recent sessions
  - per-exercise history

### FR-007 Body Composition Tracking

- The app must support local CRUD for InBody scan data.
- Progress surfaces must render body-composition trends from persisted scans.

### FR-008 Database Lifecycle

- The app must expose local DB health/status.
- The user must be able to rebuild the DB cache from Sheets inside the app.
- Rebuild actions must execute the actual importer workflow, not a placeholder status update.

### FR-009 Bidirectional Log Sync

- The app must reconcile workout log differences between Google Sheets and the local DB.
- Sync must be deterministic and idempotent per row.
- Sync state must persist row-level checkpoints.
- Conflict policy must be user-configurable in Settings.
- The app must persist an audit trail for sync decisions so conflicts are reviewable after the fact.

### FR-010 Reliability and Error Visibility

- Google auth failures, HTTP failures, and parse failures must surface actionable messages.
- Expired/revoked OAuth tokens must be recoverable through re-auth.
- Remote refresh and sync flows must never silently discard logs.

## 6. Non-Functional Requirements

### NFR-001 Native-First UX

- The app must behave as a real macOS application with SwiftUI/AppKit hosting.
- Core flows must remain keyboard navigable and readable on laptop displays.

### NFR-002 Local Durability

- Config, OAuth tokens, DB state, and local artifacts must live under App Support paths.
- Destructive overwrites must always archive or checkpoint first.

### NFR-003 Deterministic Backend Behavior

- Parsing, repairs, and sync resolution must be deterministic for the same inputs.
- Conflict rules must not depend on non-deterministic ordering.

### NFR-004 Security

- No API keys or tokens may be hardcoded in source.
- Sensitive credentials must remain local to the user profile.

## 7. Traceability to Current Native Code

- App shell and routes: `native/SamsWorkoutNative/Sources/WorkoutDesktopApp`
- Domain logic: `native/SamsWorkoutNative/Sources/WorkoutCore`
- Integrations: `native/SamsWorkoutNative/Sources/WorkoutIntegrations`
- Persistence: `native/SamsWorkoutNative/Sources/WorkoutPersistence`
- Test suites: `native/SamsWorkoutNative/Tests/*`
