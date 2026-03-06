# IMPLEMENTATION_PLAN (Native Swift Addendum - Sync Review and Progression)

Last updated: 2026-03-06
Runtime scope: `native/SamsWorkoutNative`
Addendum to active native docs:
- `IMPLEMENTATION_PLAN_2026-03-06_1545_native-swift.md`

## Phase 2 Addendum - Staged Generation Hardening

Deliver:

- deterministic validation for Stage 1 supplemental exercise selection
- one bounded low-token correction retry for malformed Stage 1 output
- surfaced pipeline telemetry in the Generate Plan page

Verification:

- unit tests for selection validation and telemetry propagation
- full native `swift test`

## Phase 4 Addendum - Sync Review and Repair

Deliver:

- Settings conflict review actions backed by sync audit rows
- gateway repair workflow that rewrites both stores and checkpoints
- new audit rows for manual repair events

Verification:

- resolver/repair tests
- coordinator workflow tests

## Phase 5 Addendum - Progression Insight Surface

Deliver:

- deterministic progression insight model derived from DB history
- Progress page surface for recent progression signals and recommendations
- generation/runtime reuse of the same progression insight logic where applicable

Verification:

- unit tests for progression insight derivation
- coordinator/UI state tests
