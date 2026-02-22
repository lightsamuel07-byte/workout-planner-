# FRONTEND_GUIDELINES (Swift Native Track)

Last updated: 2026-02-22

## 1. UI Architecture

- SwiftUI navigation with feature-scoped view models
- Unidirectional data flow per feature (View -> ViewModel -> Service)
- Reusable design tokens + shared components

## 2. Page Parity Targets

Must exist in native app:
- Dashboard
- Generate Plan
- View Plan
- Log Workout
- Progress
- Weekly Review
- Exercise History
- DB Status

## 3. Interaction Standards

- Keyboard navigable controls
- Visible loading and error states
- Explicit success/failure feedback for writes
- No silent failures

## 4. Accessibility

- VoiceOver labels for controls and critical metrics
- Focus order aligned to workflow
- High-contrast color usage

## 5. Design System Application

- Preserve current token intent from `DESIGN_SYSTEM.md`
- Avoid introducing non-documented token values without explicit update
- Keep exercise cards and day cards semantically consistent with current app behaviors

## 6. Local-First UX

- First-run setup wizard for API key + sheet auth
- Clear source labels (Google Sheets vs Local DB cache)
- Recovery actions surfaced in-app (re-auth, rebuild DB cache)
