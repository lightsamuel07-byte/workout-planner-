# LESSONS

Last updated: 2026-02-05

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

## Session Corrections (2026-02-05)

- Correction received: canonical docs did not exist, and work needed to continue in doc-locked mode.
- New rule: when canonical docs are missing and user requests doc-locked workflow, create baseline canonical docs from the current codebase before feature work.
- Correction received: mobile screenshots exposed spacing/border density issues that code-only review understated.
- New rule: for UX phases, validate with real device screenshots (or equivalent) before finalizing mobile layout recommendations.
