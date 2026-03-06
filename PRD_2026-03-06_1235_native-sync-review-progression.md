# PRD (Native Swift Addendum - Sync Review and Progression)

Last updated: 2026-03-06
Runtime scope: `native/SamsWorkoutNative`
Addendum to active native docs:
- `PRD_2026-03-06_1545_native-swift.md`

## 1. Purpose

This addendum locks the requirements for:

- staged generation hardening and telemetry visibility,
- conflict review and manual repair for bidirectional sync,
- explicit progression insights derived from local DB history.

## 2. Additional Functional Requirements

### FR-003A Staged Generation Hardening

- The Stage 1 supplemental exercise-selection pass must be validated locally before the app uses it to build targeted DB context.
- Stage 1 validation must check:
  - Tuesday / Thursday / Saturday lists are all present
  - each supplemental day has at least 5 exercises
  - the same exercise does not appear across multiple supplemental days
- If Stage 1 validation fails, the app may perform one bounded low-token correction retry before falling back to generic DB context.
- The app must surface generation telemetry after a run:
  - pipeline mode
  - total input/output token counts
  - per-stage token counts
  - per-stage duration
  - distillation compression summary when available

### FR-009A Conflict Review and Manual Repair

- Settings must surface recent sync conflict rows using persisted sync audit events.
- Conflict review rows must show:
  - sheet name
  - day label
  - source row
  - exercise name
  - sheet log
  - DB log
  - resolved log
  - resolution metadata
- For rows marked as conflicts, the user must be able to trigger:
  - `Apply Google Sheets Value`
  - `Apply Local DB Value`
- A manual repair action must:
  - write the chosen log to Google Sheets column `H`
  - write the chosen log to the local DB session row
  - upsert row-level sync checkpoint state
  - append a new sync audit event describing the manual repair
- Manual repair must be deterministic and idempotent for repeated clicks on the same chosen side.

### FR-006A Explicit Progression Insights

- The app must compute explicit progression insights from local DB history instead of relying only on prompt-time interpretation.
- Each progression insight must include:
  - exercise name
  - day hint when available
  - session count
  - last prescription
  - latest RPE when available
  - load trend
  - progression signal (`LOCK`, `PROGRESS`, `NEUTRAL`)
  - progression reason
  - recommendation text
- First-pass deterministic signal rules for DB-derived insights:
  - `PROGRESS` when the latest logged RPE is `<= 7.0` and there are at least 2 logged sessions
  - `LOCK` when the latest logged RPE is `>= 8.5`
  - `NEUTRAL` otherwise or when logged history is insufficient
- The app must surface recent progression insights in the native UI.
- The generation pipeline must continue to use explicit distilled progression recommendations as structured input rather than raw logs alone.

## 3. Non-Functional Requirements

### NFR-003A Bounded Multi-Call Generation

- Additional generation calls must stay purpose-specific and low-token.
- The correction retry for Stage 1 is bounded to one retry per generation run.
- Repeated large-context prompts are not allowed when a smaller corrective prompt can achieve the same outcome.

### NFR-003B Repair Traceability

- Manual repair actions must leave an audit trail distinct from automatic sync conflict resolution.
- The app must preserve enough metadata to review what value was chosen and where it was written.
