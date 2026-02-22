# BACKEND_STRUCTURE (Swift Native Track)

Last updated: 2026-02-22

## 1. Topology

Native in-process architecture (no separate server process):

- UI (SwiftUI)
- Domain services (pure Swift)
- Integrations (Anthropic + Google Sheets)
- Local persistence (GRDB/SQLite)

## 2. Module Responsibilities

### `WorkoutCore`
- Fort parser/compiler
- Exercise normalization
- Plan validator
- Progression rule engine
- Shared domain models

### `WorkoutIntegrations`
- Anthropic API client
- Google Sheets API client
- Auth/session token handling

### `WorkoutPersistence`
- GRDB migrations
- Repositories (`exercises`, `workout_sessions`, `exercise_logs`, alias tables)
- Sync upsert transactions

### `WorkoutDesktopApp`
- Feature coordinators and view models
- Navigation/routing state
- Setup/auth screens
- Error handling and user messaging

## 3. Data Flow

### Generate Plan
1. UI collects Mon/Wed/Fri and program status.
2. Core builds prompt context.
3. Integrations call Anthropic.
4. Core validates/repairs output.
5. Integrations write to Google Sheets.
6. Persistence stores metadata/cache.

### Log Workout
1. Integrations read current week from Sheets.
2. UI captures logs.
3. Integrations write Column H logs to Sheets.
4. Persistence syncs logs to SQLite via GRDB transaction.

### Analytics
1. Integrations read sheet history and/or persistence cache.
2. Core computes progression, volume, compliance metrics.
3. UI renders charts/cards.

## 4. Reliability Constraints

- Idempotent sync writes
- Strict schema mapping for A:H
- No destructive overwrite without archival behavior
- Explicit error surfaces on auth/network failures

## 5. Security Constraints

- No hardcoded API keys
- Keychain-backed secret storage
- Local OAuth tokens only in user profile App Support paths
