# IMPLEMENTATION_PLAN (Swift Native Rewrite)

Last updated: 2026-02-22

## Phase 0 - Rewrite Charter and Specs (Current)

Goals:
- Lock rewrite scope, architecture, and parity constraints.
- Create timestamped canonical docs for native track.

Deliverables:
- `TECH_STACK_2026-02-22_1018_swift-native.md`
- `BACKEND_STRUCTURE_2026-02-22_1018_swift-native.md`
- `FRONTEND_GUIDELINES_2026-02-22_1018_swift-native.md`
- `IMPLEMENTATION_PLAN_2026-02-22_1018_swift-native.md`
- Parity matrix file for migration tracking.

## Phase 1 - Native Foundation

Goals:
- Create native workspace and module boundaries.
- Add baseline models, protocols, and app shell.

Deliverables:
- Swift package/project scaffold with modules:
  - `WorkoutDesktopApp`
  - `WorkoutCore`
  - `WorkoutIntegrations`
  - `WorkoutPersistence`
- Basic app navigation shell.

## Phase 2 - Core Domain Port

Goals:
- Port and verify domain logic from Python.

Deliverables:
- Exercise normalization engine
- Fort parser/compiler
- Plan validator + progression rules
- Golden tests against known Python fixtures

## Phase 3 - Integrations Port

Goals:
- Port Anthropic and Google Sheets connectivity.

Deliverables:
- Auth/session manager
- Sheets read/write client
- Anthropic generation client

## Phase 4 - Persistence and Sync

Goals:
- Replace Python SQLite layer with GRDB implementation.

Deliverables:
- GRDB schema + migrations
- Sync services and repositories
- DB status metrics hooks

## Phase 5 - Full Native UI

Goals:
- Implement all user workflows in SwiftUI.

Deliverables:
- All page parity targets wired end-to-end
- Setup flow and recovery UI

## Phase 6 - QA Hardening

Goals:
- Achieve regression confidence before cutover.

Deliverables:
- Automated test suite (unit + integration)
- Workflow smoke checklist pass
- Bug triage and closure

## Phase 7 - Packaging and Cutover

Goals:
- Produce local signed `.app` and move day-to-day use to native app.

Deliverables:
- Signed local `.app`
- Runbook for updates, backup, and recovery
