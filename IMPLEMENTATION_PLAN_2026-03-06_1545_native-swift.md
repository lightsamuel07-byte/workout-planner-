# IMPLEMENTATION_PLAN (Swift Native Track)

Last updated: 2026-03-06
Supersedes for active runtime: `IMPLEMENTATION_PLAN.md`, `IMPLEMENTATION_PLAN_2026-02-22_1018_swift-native.md`
Runtime scope: `native/SamsWorkoutNative`

## Phase 0 - Canonical Native Documentation

Goals:

- Realign the canonical spec with the active native app.
- Preserve historical web-app docs without overwriting them.

Delivered:

- Native timestamped docs for PRD, app flow, tech stack, design system, frontend guidelines, backend structure, and implementation plan.

## Phase 1 - Native Foundation (Complete)

Delivered:

- Swift package structure and module split
- native app shell and setup flow
- route/navigation baseline

## Phase 2 - Domain and Generation Parity (In Progress)

Delivered:

- Fort parsing/compiler pipeline
- deterministic plan validation and repairs
- modularized `LiveAppGateway`
- staged generation foundation:
  - exercise selection
  - athlete-state distillation
  - plan synthesis telemetry

Next:

- verify and commit staged-generation implementation cleanly

## Phase 3 - Integrations Runtime (Complete)

Delivered:

- Anthropic runtime integration
- Google Sheets read/write integration
- OAuth refresh-token recovery
- plan load error surfacing

## Phase 4 - Persistence and Sync (In Progress)

Delivered:

- GRDB migrations and analytics queries
- DB rebuild flow
- InBody persistence
- row-level bidirectional sync checkpoints

Current session target:

- add configurable sync conflict policy
- add persisted sync audit trail

## Phase 5 - Native UI Coverage (Active)

Delivered:

- Dashboard
- Generate Plan
- View Plan
- Progress
- Weekly Review
- Exercise History
- Settings

Current session target:

- expose sync hardening controls and audit visibility in Settings

## Phase 6 - QA Hardening (Active)

Delivered:

- broad native unit/integration suite
- live smoke coverage for sheet naming sanity

Current session target:

- add regression coverage for config migration defaults, sync policy, sync audit, and distillation

## Phase 7 - Packaging and Daily Use (Active)

Delivered:

- local build script
- signed local `.app`
- native app is the primary daily-use runtime
