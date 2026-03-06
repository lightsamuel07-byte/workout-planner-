# BACKEND_STRUCTURE (Swift Native Track)

Last updated: 2026-03-06
Supersedes for active runtime: `BACKEND_STRUCTURE.md`, `BACKEND_STRUCTURE_2026-02-22_1018_swift-native.md`
Runtime scope: `native/SamsWorkoutNative`

## 1. Topology

The native app uses an in-process backend architecture:

- SwiftUI/AppKit UI
- `WorkoutCore` domain logic
- `WorkoutIntegrations` for Anthropic + Google Sheets
- `WorkoutPersistence` for GRDB/SQLite

There is no standalone backend server.

## 2. Module Responsibilities

### `WorkoutDesktopApp`

- `AppCoordinator`
- route state and feature orchestration
- setup/config persistence integration
- live gateway orchestration
- user-visible status/error messaging

### `WorkoutCore`

- Fort parsing/compiler logic
- plan validation
- progression directives
- exercise normalization
- markdown/sheet plan parsing support

### `WorkoutIntegrations`

- Anthropic client
- Google Sheets client
- HTTP layer and OAuth token refresh

### `WorkoutPersistence`

- GRDB migrations
- workout session / exercise / log repositories
- InBody persistence
- bidirectional sync checkpoint persistence
- bidirectional sync audit persistence

## 3. Primary Data Flows

### Flow A: Generate Weekly Plan

1. Coordinator collects Fort inputs and setup state.
2. Gateway normalizes Fort input and loads progression context.
3. Optional staged call selects target supplemental exercises.
4. Local DB rows are distilled into athlete-state context.
5. Anthropic synthesizes the plan.
6. Deterministic repairs and validation run locally.
7. App saves/archives the local plan and rewrites the target sheet tab.

### Flow B: Refresh Plan Snapshot

1. Gateway chooses local snapshot or remote sheet source.
2. If remote refresh is requested, the gateway first runs bidirectional log reconciliation.
3. Reconciled rows are parsed into `PlanSnapshot`.

### Flow C: Rebuild Database Cache

1. Gateway reads historical weekly sheets.
2. Persistence rebuild/import syncs rows into GRDB.
3. Coordinator refreshes analytics from the rebuilt DB.

### Flow D: Bidirectional Sync

1. Gateway loads sheet rows, DB rows, and prior sync checkpoints.
2. Resolver computes the row decision using the configured conflict policy.
3. Required pull/push mutations are applied.
4. New `log_sync_state` checkpoints are upserted.
5. Sync audit events are written for each resolved row.

## 4. Persistence Schema

Current and required tables:

- `exercises`
- `workout_sessions`
- `exercise_logs`
- `exercise_aliases`
- `inbody_scans`
- `log_sync_state`
- `sync_audit_events`

## 5. Reliability Constraints

- Google Sheets mapping must remain locked to `A:H`.
- Sync logic must be idempotent for repeated runs.
- Conflict resolution must be deterministic and reviewable after the run.
- Local persistence must never silently discard a non-empty log.

## 6. Security Constraints

- Secrets remain local to the user profile.
- API keys are config-backed, not source-backed.
- OAuth tokens are refreshed locally and stored in App Support paths.
