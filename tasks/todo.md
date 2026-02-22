# Session Plan - Bug Scan (2026-02-21)

## Checklist
- [x] Confirm this session plan with the user before any code changes.
- [x] Baseline check: inspect git status and identify changed files that may affect bug risk.
- [x] Run full automated verification suite:
  - [x] `python3 -m unittest discover -s tests -p "test_*.py" -v`
  - [x] `python3 -m compileall app.py pages src tests main.py`
- [x] Run targeted high-risk validations from current progress focus:
  - [x] Fort parser/compiler tests (`tests/test_fort_compiler.py`) via full suite coverage
  - [x] Generation-context and validator tests (`tests/test_generation_context.py`, `tests/test_plan_validator.py`) via full suite coverage
- [x] Perform static bug scan for obvious correctness issues:
  - [x] fragile exception handling
  - [x] stale session-state paths
  - [x] schema assumptions (`A:H`, weekly sheet naming)
- [x] Produce findings-first report with severity and file/line references.
- [x] If no bugs found, explicitly state no findings and residual risks/testing gaps.

## Review (fill in at end of session)
- Findings:
- Confirmed 4 concrete bugs:
  - archived weekly tabs are incorrectly included in weekly sheet selection due unanchored regex.
  - weekly volume metric is computed per-day (not per-week), causing wrong dashboard value.
  - main-lift progression sorts by raw date label string, producing wrong "current" load.
  - local markdown plan parser only recognizes uppercase day headers and fails on `## Monday`.
- Decisions:
- No production code edits were applied in this scan-only pass.
- Next steps:
- Apply targeted fixes for the 4 findings and add regression tests for regex anchoring, analytics date handling, weekly aggregation, and day-header parsing.
