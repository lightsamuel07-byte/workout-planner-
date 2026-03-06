# TECH_STACK (Swift Native Track)

Last updated: 2026-03-06
Supersedes for active runtime: `TECH_STACK.md`, `TECH_STACK_2026-02-22_1018_swift-native.md`
Runtime scope: `native/SamsWorkoutNative`

## 1. Runtime and Platform

- Language: Swift
- Swift tools version: 6.2 (`Package.swift`)
- Platform target: macOS 14+
- UI stack: SwiftUI with AppKit hosting
- Packaging target: local signed `.app`

## 2. Project Structure

- App shell and feature logic:
  - `native/SamsWorkoutNative/Sources/WorkoutDesktopApp`
- Domain/core logic:
  - `native/SamsWorkoutNative/Sources/WorkoutCore`
- External integrations:
  - `native/SamsWorkoutNative/Sources/WorkoutIntegrations`
- Persistence:
  - `native/SamsWorkoutNative/Sources/WorkoutPersistence`
- Tests:
  - `native/SamsWorkoutNative/Tests/*`

## 3. Dependencies

- `GRDB.swift` `7.0.0+`
- Foundation / URLSession / Codable
- SwiftUI
- AppKit
- macOS Keychain and App Support file storage patterns

## 4. External Services

- Anthropic Messages API
- Google Sheets API
- Google OAuth token exchange / refresh

## 5. Data Stores

- Durable shared source of truth: Google Sheets weekly tabs
- Local analytics + cache DB:
  - `~/Library/Application Support/SamsWorkoutApp/data/workout_history.db`
- Local config:
  - `~/Library/Application Support/SamsWorkoutApp/config.json`
- OAuth token:
  - `~/Library/Application Support/SamsWorkoutApp/token.json`
- Local artifacts:
  - `~/Library/Application Support/SamsWorkoutApp/output/`

## 6. Build / Test Commands

From `native/SamsWorkoutNative`:

- `swift build`
- `swift test`
- `bash scripts/build_local_app.sh`

If `xcode-select` points at Command Line Tools, commands may require:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`

## 7. Release Output

- App bundle:
  - `native/SamsWorkoutNative/dist/SamsWorkoutNative.app`
- Local signing is performed by the build script.

## 8. Compatibility Constraints

- Preserve both weekly sheet naming formats:
  - `Weekly Plan (M/D/YYYY)`
  - `(Weekly Plan) M/D/YYYY`
- Preserve the locked `A:H` sheet schema.
- Preserve canonical workout log formatting in sheet log cells.

## 9. Backend Interaction Constraints

- No separate backend server or web API is in scope.
- All API interaction happens from the native app.
- Smaller staged API calls are allowed when total token budget remains bounded and repeated context is minimized.
