# LESSONS

Last updated: 2026-02-28

## Core Lessons to Preserve

1. Keep the Google Sheets schema locked to 8 columns (`A:H`):
   - `A Block`, `B Exercise`, `C Sets`, `D Reps`, `E Load`, `F Rest`, `G Notes`, `H Log`.
   - `src/sheets_reader.py`, `src/sheets_writer.py`, and `pages/workout_logger.py` all depend on this layout.

2. Support both weekly sheet naming patterns in all sheet discovery logic:
   - `Weekly Plan (M/D/YYYY)`
   - `(Weekly Plan) M/D/YYYY`

3. Preserve the canonical log format for workout logging:
   - `performance | RPE x | Notes: ...`
   - RPE parsing and DB sync depend on this convention.

4. Preserve progressive overload guardrails in AI generation:
   - No rep/load ranges in final output.
   - Hard constraints around biceps rotation, equipment rules, and dumbbell load parity.

5. Treat local markdown plans and Google Sheets as dual data sources:
   - View flows should fall back to Sheets when local files are absent.
   - This is required for Streamlit Cloud behavior.

6. Streamlit auth must support multiple environments:
   - Local OAuth token flow (`token.json`)
   - Service account file
   - Streamlit Cloud secrets (`gcp_service_account`)

7. Keep root-level utility scripts side-effect free on import:
   - `unittest discover` imports modules matching `test_*.py`.
   - Any top-level API calls in those files can hang audits and CI checks.
   - Run network/manual flows only inside `main()` guarded by `if __name__ == "__main__":`.

8. Fort parsing cannot assume cluster-only programming:
   - Fort program structures vary by cycle (`Ignition/Cauldron/Breakpoint`, etc.).
   - Section detection and preamble stripping must be program-agnostic and alias-driven.

## Session Corrections (2026-02-05)

- Correction received: canonical docs did not exist, and work needed to continue in doc-locked mode.
- New rule: when canonical docs are missing and user requests doc-locked workflow, create baseline canonical docs from the current codebase before feature work.
- Correction received: mobile screenshots exposed spacing/border density issues that code-only review understated.
- New rule: for UX phases, validate with real device screenshots (or equivalent) before finalizing mobile layout recommendations.

## Session Corrections (2026-02-15)

- Correction received: cloud-generated markdown/explanation files were not locally accessible to the user.
- New rule: for Streamlit Cloud flows, persist generation explanation/validation metadata in Google Sheets and surface it in app fallback views (do not assume local filesystem visibility).
- Audit correction: odd DB loads could slip through for DB squat/press variants due broad main-lift token matching.
- New rule: main-lift exemptions must exclude DB-tagged exercise names; only barbell main lifts are exempt from DB parity enforcement.
- Correction received: Generate button clicks can be lost if session state gets stuck as "in progress".
- New rule: generation flow must use an explicit request flag and stale-state recovery (timeout reset) so spinner/start state is reliable after reruns.
- Correction received: biceps rotation validator flagged false repeats when notes referenced other-day grip sequence text.
- New rule: grip detection must prioritize explicit per-exercise grip declarations and treat mixed note signals as ambiguous (not a repeat violation).

## Session Corrections (2026-02-17)

- Correction received: Fort day inputs are not always cluster-based; older programs use different section naming and flow.
- New rule: generation context must use a deterministic, program-agnostic Fort parser/compiler with section alias mapping, rather than hard-coded cluster section assumptions.
- Correction received: user expected overnight-depth scope, not a fast foundation slice.
- New rule: when tackling large feature requests, explicitly separate foundation slice vs full-scope deliverables upfront and continue through full scope when requested.

## Session Corrections (2026-02-21)

- Correction received: test-week generation still emitted section labels/instruction lines as exercises after initial parser hardening.
- New rule: Fort parser must explicitly filter instruction-like lines (`TIPS`, `Rest ...`, `Right into...`, etc.) from exercise anchors, even when they are short.
- Correction received: split-squat alias matching can become overbroad if canonicalization strips too many modifiers.
- New rule: alias canonicalization should be minimal and deterministic; use targeted variant/prefix expansion for expected anchors instead of aggressive token stripping.
- Correction received: even with better parsing, Fort-day outputs can still include section/instruction rows as exercises if we only do insert-only repair.
- New rule: deterministic Fort repair must rebuild Fort days from canonical parsed anchors (ordered replace), not just append missing anchors.

## Session Corrections (2026-02-22)

- Correction received: DB Status exposed a "Rebuild DB Cache" action that did not run any importer and left users with sparse history.
- New rule: any user-facing recovery/maintenance action button must execute the underlying workflow end-to-end (never placeholder status-only handlers).
- Correction received: DB mode text reported Anthropic readiness from environment only, conflicting with app-config-based runtime behavior.
- New rule: status surfaces must derive from the same configuration source used by runtime execution paths.
- Correction received: repeated live runs can collide when archive names rely on deterministic timestamps.
- New rule: all archival writes must guarantee unique output names (suffix fallback when collision occurs).
- Correction received: fixed-date live E2E generation can accidentally create far-future weekly tabs (e.g., year `2099`) in production sheets.
- New rule: generation sheet naming must include a runtime date sanity guard (clamp far-future/past reference dates to current week) and maintain a live test that fails if `Weekly Plan` tabs with `2099` appear.

## Session Corrections (2026-02-26)

- Correction received: planning and scan scope was initially framed as mixed-stack while project runtime had already moved to native macOS.
- New rule: before creating any plan or running checks, confirm active runtime scope from latest progress/context and constrain execution to that runtime (native Swift modules first when native track is active).

## Session Corrections (2026-02-28)

- Correction received: Fort section aliases change every 4 weeks, so static alias lists alone are insufficient.
- New rule: Fort parsing must include deterministic dynamic-header inference (header semantics + exercise cues + section position), not just hardcoded section names.
- Correction received: conditioning inference overmatched accessory rows because `ROW` was treated as a generic cardio cue.
- New rule: conditioning cues must be machine/cardio-specific (`ROWERG`, `SKIERG`, etc.); avoid ambiguous tokens that overlap accessory lift names.
- Correction received: generated plans can still look superficially valid while leaking section headers/table labels as exercises.
- New rule: validator must hard-fail Fort pseudo-exercises (`PREPARE TO ENGAGE`, `THE PAY OFF`, `THAW`, `METERS`, `EXAMPLES`, etc.) so correction loop is forced.
- Correction received: SSE streaming fixtures can fail if parser assumes blank-line frame separators only.
- New rule: SSE parser must flush pending `data:` on both blank-line boundaries and when a new `event:` line begins.
- Correction received: stream callback propagation can fail strict Swift concurrency checks.
- New rule: callbacks crossing actor boundaries must be `@Sendable`, and UI updates from stream callbacks must hop explicitly to `MainActor`.
