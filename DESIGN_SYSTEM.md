# DESIGN_SYSTEM

Last updated: 2026-02-05
Source of truth: `src/design_system.py` and `assets/styles.css`

## 1. Design Principles

- Mobile-first interactions.
- Conservative motion and clear hierarchy.
- Teal/mint accent for primary actions and progress emphasis.
- Reusable component primitives via shared helpers.

## 2. Color Tokens

### Light Theme

- `primary`: `#000000`
- `primary_variant`: `#1A1A1A`
- `accent`: `#00D4AA`
- `accent_dark`: `#00B894`
- `background`: `#FAFAFA`
- `surface`: `#FFFFFF`
- `success`: `#00D4AA`
- `warning`: `#FF6B35`
- `error`: `#DC3545`
- `info`: `#3B82F6`
- `text_primary`: `#000000`
- `text_secondary`: `#6B7280`
- `text_disabled`: `#9CA3AF`
- `border_strong`: `#000000`
- `border_medium`: `#D1D5DB`
- `border_light`: `#E5E7EB`

### Dark Theme

- `primary`: `#FFFFFF`
- `primary_variant`: `#E5E5E5`
- `accent`: `#00D4AA`
- `accent_dark`: `#00B894`
- `background`: `#0F0F0F`
- `surface`: `#1A1A1A`
- `success`: `#00D4AA`
- `warning`: `#FF6B35`
- `error`: `#DC3545`
- `info`: `#3B82F6`
- `text_primary`: `#FFFFFF`
- `text_secondary`: `#9CA3AF`
- `text_disabled`: `#6B7280`
- `border_strong`: `#FFFFFF`
- `border_medium`: `#374151`
- `border_light`: `#1F2937`

## 3. Spacing Tokens

- `xs`: `0.25rem`
- `sm`: `0.5rem`
- `md`: `1rem`
- `lg`: `1.5rem`
- `xl`: `2rem`
- `2xl`: `3rem`

## 4. Typography Tokens

- Body font: `'Inter', system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif`
- Heading font: `'Space Grotesk', 'Inter', sans-serif`

Common scale usage in current UI:
- Metric value: `1.875rem`
- Section header labels: `0.75rem` uppercase
- Main page header: approximately `2.5rem` desktop, reduced on mobile

## 5. Motion Tokens

- `transition-fast`: `150ms cubic-bezier(0.4, 0, 0.2, 1)`
- `transition-standard`: `250ms cubic-bezier(0.4, 0, 0.2, 1)`
- `transition-slow`: `350ms cubic-bezier(0.4, 0, 0.2, 1)`

Key animations:
- Metric/card hover lift.
- Skeleton shimmer (`1.5s` infinite).
- Main area fade-in on page render.

## 6. Shape and Layout Tokens

- Standard radius: `8px`
- Large radius usage: `12px` (hero/info cards)
- Default control/card border: `1px` (subtle)
- Strong emphasis border for active/today cards: `2px`
- Border width tokens:
  - `border-width-subtle`: `1px`
  - `border-width-strong`: `2px`

## 7. Responsive Breakpoints

- Tablet/mobile threshold: `max-width: 768px`
- Small phone threshold: `max-width: 480px`

Mobile behavior requirements currently used:
- Inputs/buttons minimum touch height: `48px` on mobile override.
- Base control minimum height: `44px`.
- Column stacks into single-column behavior.
- Main content horizontal padding reduced for narrow screens.

## 8. Core Component Styles

- Buttons:
  - Default: bordered, `8px` radius, subtle lift on hover.
  - Primary/accent: teal background with darker hover state.

- Metric cards:
  - Surface background, light border, hover lift.

- Exercise cards:
  - Strong border, block/exercise emphasis, 4-cell metric grid.

- Day cards:
  - Weekly calendar card with optional `today` accent state.

- Empty states:
  - Centered icon/title/description with padded container.

- Progress bars:
  - Accent fill on neutral track with animated width transitions.

## 9. Theming Implementation Notes

- Theme switching is controlled by `st.session_state['dark_mode']`.
- CSS variables define both light and dark modes.
- `get_colors()` in `src/design_system.py` provides runtime color maps for inline-rendered components.

## 10. Current Consistency Note

- Most shared styling follows tokenized values.
- Some page-level inline styles still include hardcoded values; these should be normalized in future UX refinement phases.
