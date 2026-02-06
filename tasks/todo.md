# Session Plan - Apple-Style UX Polish (2026-02-06)

## Checklist
- [x] Confirm this session plan with the user before any code changes.
- [x] Add Apple-style callout + divider utilities in `assets/styles.css` (no left-border accents, subtle background/border, dark-mode tokens).
- [x] Normalize remaining accent-heavy callouts to the new classes:
  - `app.py` sidebar connection status
  - `pages/generate_plan.py` usage tips + warning blocks
  - `pages/progress.py` info card
  - `pages/workout_logger.py` empty/troubleshooting + save-status banners
  - `pages/view_plans.py` notes blocks
  - `pages/weekly_review.py` day/status callouts
- [x] Remove remaining accent underlines in plan exercise headers (use neutral border-light) and reduce shouty uppercase where safe.
- [x] Update `src/design_system.py` helper(s) only if needed to avoid inline duplication; keep token usage consistent.
- [x] Create a new timestamped design-system snapshot documenting any new callout tokens or component rules (do not overwrite `DESIGN_SYSTEM.md`).
- [x] Run validation: `python3 -m compileall app.py pages src`, `python3 -m unittest discover -s tests -p "test_*.py" -v`, `python3 -m streamlit run app.py --server.headless true --server.port 85xx`.
- [x] Update `progress.txt` with work completed and next steps; fill Review section here.
- [ ] Commit and push to git.

## Review (fill in at end of session)
- Findings:
  - Replaced left-border callouts with Apple-style neutral callouts across key pages.
  - Normalized plan header accents to neutral dividers; reduced uppercase emphasis in exercise headers.
  - Added callout CSS variables for light/dark themes and updated Streamlit message styling to match.
- Decisions:
  - Documented new callout utilities in a timestamped design-system snapshot.
- Next steps:
  - Push changes to git.
