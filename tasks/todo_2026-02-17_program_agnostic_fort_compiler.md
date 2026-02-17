# Session Plan - Program-Agnostic Fort Parser + Deterministic Compiler (2026-02-17)

## Checklist
- [x] Resolve doc precedence conflict (`progress.txt` vs `IMPLEMENTATION_PLAN.md`) for current phase.
- [x] Define canonical parsing schema for variable Fort structures (Cluster, Build Up/Working/Back Off, Breakpoint, named sections like Ignition/Cauldron/THAW).
- [x] Implement parser module with section alias mapping and exercise extraction.
- [x] Add deterministic day-structure synthesis layer for Mon/Wed/Fri normalization into canonical markdown blocks.
- [x] Integrate parser output into generation flow with confidence scoring + fallback behavior.
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
- Decisions:
  - Keep Claude responsible for final wording and complete plan synthesis, but provide deterministic section/exercise anchors from parser as hard prompt constraints.
  - Use parser confidence as visibility signal only (no blocking), with raw-text fallback when parser confidence is weak.
- Next steps:
  - Generate a live non-cluster week and confirm Mon/Wed/Fri section/exercise anchors are preserved.
  - If anchors still drift, add deterministic post-generation validator for required Fort-day exercise presence.
