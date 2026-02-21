# Session Plan - Test Week Fort Hardening (2026-02-21)

## Scope
Harden Fort parsing and generation safeguards so one-week test blocks (1RM/conditioning test format) convert reliably without false fidelity failures.

## Checklist
- [x] Add test coverage first for test-week section headers and anchors (1RM TEST, TARGETED WARM-UP, MAX TEST, GARAGE TEST naming).
- [x] Extend Fort parser section rules to recognize test-week vocabulary and map into canonical intent buckets.
- [x] Improve exercise-candidate filtering so section labels like `1RM TEST` are not treated as exercises.
- [x] Add alias-aware fidelity matching for split-squat swap variants to avoid false `fort_missing_anchor` violations.
- [x] Run full regression suite and compile checks.
- [x] Run targeted parser smoke check against provided 2/23, 2/25, 2/27 text.
- [x] Update `tasks/todo_2026-02-21_test-week-hardening.md` review section.
- [x] Update `progress.txt` with phase linkage and outcomes.
- [x] Update `LESSONS.md` only if user correction occurs during implementation (no corrections this pass, no LESSONS update required).

## Verification Plan
- Unit tests: `tests/test_fort_compiler.py` additions for test-week parsing + alias fidelity.
- Full regression: `python3 -m unittest discover -s tests -p "test_*.py" -v`.
- Syntax check: `python3 -m compileall pages src tests main.py`.
- Behavior check: parser output for provided test-week text shows correct section extraction and no mislabeled test headers as exercises.

## Review
- Implemented in `src/fort_compiler.py`:
  - added test-week section aliases for parser classification:
    - `1RM TEST`/`3RM TEST` -> `strength_work`
    - `TARGETED WARM-UP` -> `prep_mobility`
    - `GARAGE ... TEST` and benchmark modality test headers -> `conditioning`
    - `MAX PULL UP TEST` / `MAX PUSH-UP TEST` -> `strength_work`
  - seeded conditioning section headers as anchors when header includes modality benchmark text (e.g., `GARAGE - 2K BIKEERG`), preserving test targets in compiled anchors.
  - expanded alias map construction/matching with canonicalized alias keys so swap rules like `Split Squat -> Heel-Elevated Goblet Squat` match Fort anchors such as `DB SPLIT SQUAT`.
- Added tests in `tests/test_fort_compiler.py`:
  - `test_parse_fort_day_handles_test_week_headers`
  - `test_validate_fort_fidelity_handles_split_squat_swap_alias`
- Verification:
  - `python3 -m unittest tests/test_fort_compiler.py -v` passed (10 tests).
  - `python3 -m unittest discover -s tests -p "test_*.py" -v` passed (32 tests).
  - `python3 -m compileall pages src tests main.py` passed.
  - targeted parser smoke check against provided 2/23, 2/25, 2/27 input confirms:
    - `1RM TEST` not captured as exercise anchor,
    - strength, back-off, conditioning, and auxiliary sections are extracted with expected anchors.
