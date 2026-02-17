# Session Plan - Program-Agnostic Fort Parser + Deterministic Compiler (2026-02-17)

## Checklist
- [x] Resolve doc precedence conflict (`progress.txt` vs `IMPLEMENTATION_PLAN.md`) for current phase.
- [x] Define canonical parsing schema for variable Fort structures (Cluster, Build Up/Working/Back Off, Breakpoint, named sections like Ignition/Cauldron/THAW).
- [x] Implement parser module with section alias mapping and exercise extraction.
- [x] Add deterministic day-structure synthesis layer for Mon/Wed/Fri normalization into canonical markdown blocks.
- [x] Integrate parser output into generation flow with confidence scoring + fallback behavior.
- [x] Add Fort structural fidelity validator (anchors/order/load checks) against compiled metadata.
- [x] Add auto-repair correction loop that includes Fort fidelity violations.
- [x] Add historical backtest harness with aggregate scoring + per-code/per-sheet reporting.
- [x] Add regression tests using representative non-cluster Fort samples and existing cluster samples.
- [x] Validate no regressions in generation, sheets write/read, and existing validator behavior.
- [x] Update session docs (`progress.txt`, `LESSONS.md`, `tasks/...`) with findings and residual risks.

## Review
- Findings:
  - Added program-agnostic Fort parser/compiler in `src/fort_compiler.py` with canonical section intents:
    - prep, power, strength build, strength work, back-off, auxiliary, conditioning.
  - Parser now supports non-cluster section vocab (Ignition, Cauldron, Breakpoint, THAW variants) with confidence scoring and warnings.
  - `pages/generate_plan.py` preamble stripping now keys off parser-detected section boundaries instead of cluster-only regex.
  - Streamlit generation now injects deterministic Fort compiler directives into plan generation and displays parser confidence.
  - CLI generation (`main.py`) now also injects Fort compiler directives for parity.
  - Prompt logic in `src/plan_generator.py` updated to enforce parser directives and non-cluster conversion behavior.
  - Added Fort fidelity validator in `src/fort_compiler.py`:
    - checks required Fort anchors per day,
    - checks section block order drift,
    - checks explicit load presence for matched main-lift anchors in strength sections.
  - Added correction-loop hardening in `src/plan_generator.py`:
    - unresolved set now combines core-rule violations + Fort fidelity violations,
    - up to 2 correction attempts with Fort directives and fidelity summary included.
  - Added historical backtest script `scripts/backtest_generation_quality.py`:
    - validates weekly plans from XLSX export or Google Sheets,
    - emits aggregate score + per-violation code counts + per-sheet breakdown,
    - writes markdown/json reports under `output/backtest/`.
  - Ran backtest on `/Users/samuellight/Downloads/Workouts.xlsx` (6 sheets):
    - aggregate score: 93.33
    - violations concentrated in older week `Weekly Plan (222026)` (`odd_db_load` only).
- Decisions:
  - Keep Claude responsible for final wording and complete plan synthesis, but provide deterministic section/exercise anchors from parser as hard prompt constraints.
  - Use parser confidence as visibility signal only (no blocking), with raw-text fallback when parser confidence is weak.
  - Use compiler metadata as the contract for Fort-day fidelity checks; validator tolerates exercise swap aliases.
- Next steps:
  - Generate a live non-cluster week and confirm unresolved violations in `AI Generation Summary` stay at 0 for Fort fidelity.
  - If drift persists in live output, add deterministic insertion repair for missing anchors before model correction.

## Extension Pass (2026-02-17, continued)
- [x] Added deterministic Fort anchor insertion repair so missing Mon/Wed/Fri anchors are inserted before model correction.
- [x] Integrated anchor repair into generation flow on initial pass and correction passes.
- [x] Expanded DB generation context target selection:
  - include Fort anchor exercises from parsed compiler metadata,
  - include prior-week supplemental targets,
  - fallback to recent logged exercises if target list is sparse.
- [x] Added regression tests for:
  - Fort anchor insertion and missing-day reconstruction,
  - DB context selection behavior with Fort anchors and fallback.
- [x] Added repeatable quality-cycle runner (`scripts/run_quality_cycles.py`) and executed 40 cycles.
- [x] Ran post-loop backtest against `/Users/samuellight/Downloads/Workouts.xlsx`.

### Extension Validation
- `python3 -m unittest discover -s tests -p "test_*.py" -v` (29 tests, all pass)
- `python3 -m compileall app.py pages src tests main.py test_compressed_prompt.py test_format_prompt.py` (pass)
- `python3 scripts/backtest_generation_quality.py --xlsx-path "/Users/samuellight/Downloads/Workouts.xlsx" --limit 8`
  - Aggregate score: `95.0`
- `python3 scripts/run_quality_cycles.py --cycles 40 --xlsx-path "/Users/samuellight/Downloads/Workouts.xlsx" --backtest-limit 8`
  - Completed: `40/40`, Passed: `True`
