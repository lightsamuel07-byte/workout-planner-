# FRONTEND_GUIDELINES (Swift Native Track)

Last updated: 2026-03-06
Supersedes for active runtime: `FRONTEND_GUIDELINES.md`, `FRONTEND_GUIDELINES_2026-02-22_1018_swift-native.md`
Runtime scope: `native/SamsWorkoutNative`

## 1. UI Architecture

- Root shell: `NativeWorkoutRootView`
- Runtime state owner: `AppCoordinator`
- Integration boundary: `NativeAppGateway`
- Feature pages are thin SwiftUI views bound to coordinator state

## 2. State Management Rules

- Shared app state lives in `AppCoordinator`.
- Persisted user configuration flows through `AppConfigurationStore`.
- Views should trigger coordinator actions rather than talking to integrations directly.
- Gateway methods should stay async/sync exactly as defined by `NativeAppGateway`.

## 3. View Composition Rules

- Use `NavigationSplitView` for global navigation.
- Use `GroupBox` for settings, analytics, and structured control groups.
- Use `StatusBannerView` for surfaced status/error messaging.
- Keep pages in `ScrollView` containers with explicit vertical spacing.

## 4. Interaction Rules

- Long-running actions must disable their initiating button while active.
- Every write or maintenance action should expose completion state:
  - generation status
  - rebuild summary
  - bidirectional sync status
  - saved timestamps where relevant
- Avoid hidden side effects. If a background action is launched, surface its impact in the UI.

## 5. Settings Page Standards

- Database maintenance, sync controls, credentials, and configuration belong in clearly separated `GroupBox` sections.
- Conflict policy selection must be visible before the user runs sync.
- Sync audit output should be readable without leaving the app.

## 6. Accessibility and Readability

- Controls must have explicit text labels.
- Status text must remain readable without relying on color alone.
- Dense analytics sections should prioritize clear headings and concise captions over decorative chrome.

## 7. Scope Discipline

- Do not add new routes or coordinator state unless a documented feature requires it.
- Preserve current navigation parity and page naming.
