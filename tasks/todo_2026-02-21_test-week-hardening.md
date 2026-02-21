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
  - tightened alias canonicalization to avoid overbroad matching across split-squat variants (prevents unrelated swap targets from being treated as valid Fort anchors).
  - added explicit non-exercise filtering for noisy instruction lines in Fort sections (`TIPS`, `Rest ...`, `Right into...`, etc.) so they are not treated as exercise anchors.
- Implemented in `src/plan_generator.py`:
  - strengthened generation and correction prompts to explicitly forbid section headers/instruction lines from being emitted as exercises.
- Added tests in `tests/test_fort_compiler.py`:
  - `test_parse_fort_day_handles_test_week_headers`
  - `test_parse_fort_day_filters_instruction_lines_from_anchors`
  - `test_validate_fort_fidelity_handles_split_squat_swap_alias`
  - `test_validate_fort_fidelity_split_squat_alias_not_overbroad`
- Verification:
  - `python3 -m unittest tests/test_fort_compiler.py -v` passed (12 tests).
  - `python3 -m unittest discover -s tests -p "test_*.py" -v` passed (34 tests).
  - `python3 -m compileall pages src tests main.py` passed.
  - targeted parser smoke check against provided 2/23, 2/25, 2/27 input confirms:
    - `1RM TEST` not captured as exercise anchor,
    - strength, back-off, conditioning, and auxiliary sections are extracted with expected anchors.

### Follow-up Hardening (post live output review)
- Implemented in `src/fort_compiler.py`:
  - blocked narrative all-caps priority lines from being misclassified as section headers (heading-length/format gating in `_match_section_rule`).
  - normalized section lines prefixed with `COMPLETE ...` into their canonical header for matching (e.g., `COMPLETE GARAGE - 2K BIKEERG` -> `GARAGE - 2K BIKEERG`).
  - expanded non-exercise filtering for instruction noise (`Hip Circle is optional`, etc.).
  - refined alias matching so expected exercise variants can match explicit swap targets without broad canonical overreach.
- Implemented in `src/plan_generator.py`:
  - strengthened both generation and correction prompts with explicit forbidden non-exercise rows (`TIPS`, `Rest ...`, `Right into...`, section labels).
- Added/updated tests in `tests/test_fort_compiler.py`:
  - `test_parse_fort_day_does_not_treat_priority_narrative_as_section`
  - `test_parse_fort_day_strips_complete_prefix_from_section_line`
  - `test_parse_fort_day_filters_instruction_lines_from_anchors`
  - `test_validate_fort_fidelity_handles_bulgarian_swap_alias_with_variant_suffix`
- Verification:
  - `python3 -m unittest tests/test_fort_compiler.py -v` passed (15 tests).
  - `python3 -m unittest discover -s tests -p "test_*.py" -v` passed (37 tests).
  - `python3 -m compileall pages src tests main.py` passed.
  - smoke parsing for test-week snippets confirms no `TIPS`/`Rest`/`Right into` anchors and no `COMPLETE ...` anchor prefixes.

### Follow-up Hardening (structure enforcement)
- Implemented in `src/fort_compiler.py`:
  - upgraded `repair_plan_fort_anchors(...)` from insert-only behavior to deterministic Fort-day rebuild:
    - rebuilds each Fort day in parsed section/anchor order,
    - normalizes each kept exercise to strict 4-line markdown block (`###`, prescription, `Rest`, `Notes`),
    - drops non-anchor exercise blocks/noise rows on Fort days,
    - fills missing anchors with deterministic placeholders.
  - exposed richer repair summary stats (`inserted`, `dropped`, `rebuilt_days`).
- Added tests in `tests/test_fort_compiler.py`:
  - `test_repair_plan_fort_anchors_rebuilds_day_and_drops_noise_rows`
  - expanded parsing tests for priority narrative and `COMPLETE ...` header normalization.
- Verification:
  - `python3 -m unittest tests/test_fort_compiler.py -v` passed (16 tests).
  - `python3 -m unittest discover -s tests -p "test_*.py" -v` passed (38 tests).
  - `python3 -m compileall pages src tests main.py` passed.
