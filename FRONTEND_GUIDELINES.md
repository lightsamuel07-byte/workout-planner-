# FRONTEND_GUIDELINES

Last updated: 2026-02-05

## 1. Frontend Architecture

- App shell and routing: `app.py`
- Route pages: `pages/*.py`
- Shared UI helpers: `src/ui_utils.py`
- Token layer: `src/design_system.py`
- Global style layer: `assets/styles.css`

Pattern to follow:
1. Keep page-level `show()` as the route entry point.
2. Use shared header/navigation helpers first.
3. Use design tokens for colors and spacing.

## 2. Session State Conventions

Existing app-level keys:
- `current_page`
- `dark_mode`
- `password_correct`

Workflow-specific keys (examples):
- Plan generation: `plan_generation_in_progress`
- Logger: `workout_logs`, `workout_rpe`, `workout_notes`, `last_save_time`

Guidance:
- Add new keys only when necessary.
- Prefix local keys by page concern to avoid collisions.

## 3. Styling Rules

1. Prefer tokenized colors from `get_colors()` and CSS vars from `assets/styles.css`.
2. Reuse classes/components (`metric-card`, `exercise-card`, `day-card`, empty state helpers) before adding new inline style blocks.
3. Keep interaction timing conservative (150-250ms).
4. Maintain touch-target minimums for mobile (44px baseline, 48px for primary mobile controls).

## 4. Layout and Responsiveness

- Build mobile-first.
- At `<=768px`, expect stacked columns and full-width actionable controls.
- At `<=480px`, tighten typography and compact dense cards.
- Avoid horizontal scrolling in primary workflows.

## 5. Component Usage Standards

Recommended shared calls from `src/ui_utils.py`:
- `render_page_header(...)`
- `action_button(...)`
- `empty_state(...)`
- `progress_bar(...)`
- `metric_card(...)`

For new components:
- Add reusable rendering in `src/ui_utils.py` and token helpers in `src/design_system.py` where possible.
- Keep page files focused on flow and data binding.

## 6. Accessibility and Interaction Baselines

- Ensure every input has a usable label or explicit contextual cue.
- Keep keyboard-navigable controls in logical order.
- Use visible status messaging for success/error states.
- Preserve high-contrast text/background pairings from the token set.

## 7. Error and Empty State Handling

- Always provide a meaningful empty state with next action when data is missing.
- For recoverable errors, show actionable troubleshooting guidance.
- Avoid silent failures in page workflows.

## 8. Frontend Testing Checklist (Current Project Standard)

Before closing UI work, verify:
1. Desktop, tablet, and phone render paths.
2. Main route navigation and back actions.
3. Empty/error states on each touched page.
4. No regression in plan generation, plan viewing, and workout logging.
