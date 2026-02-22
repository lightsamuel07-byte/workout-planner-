# TECH_STACK (Swift Native Track)

Last updated: 2026-02-22
Supersedes for native track: Python/Streamlit runtime assumptions in `TECH_STACK.md`

## 1. Runtime and Platform

- Language: Swift 6.2+
- UI framework: SwiftUI (macOS native)
- Platform target: macOS 26.3+ (Tahoe)
- Distribution: Local signed `.app` only

## 2. Project Structure (Native)

- App shell/UI: `native/SamsWorkoutNative/Sources/WorkoutDesktopApp`
- Domain core: `native/SamsWorkoutNative/Sources/WorkoutCore`
- Integrations: `native/SamsWorkoutNative/Sources/WorkoutIntegrations`
- Persistence: `native/SamsWorkoutNative/Sources/WorkoutPersistence`
- Tests: `native/SamsWorkoutNative/Tests/*`

## 3. Dependencies

- `GRDB` for SQLite persistence and migrations
- Foundation URLSession + Codable for HTTP APIs
- Native macOS frameworks for Keychain + secure storage

## 4. External Services

- Anthropic Messages API (plan generation)
- Google Sheets API (read/write weekly plans and logs)

## 5. Data Stores

- Durable source of truth: Google Sheets
- Local analytics + cache: SQLite (`~/Library/Application Support/SamsWorkoutApp/data/workout_history.db`)
- Local artifacts: markdown/exports (`~/Library/Application Support/SamsWorkoutApp/output/`)

## 6. Secrets and Auth

- App secrets in macOS Keychain
- Google OAuth token at App Support path
- Config at App Support path (`config.json` or `config.plist`)

## 7. Build and Release

- Local development via Xcode workspace/project
- Local signing for direct `.app` distribution
- No App Store packaging in this track

## 8. Parity Requirements

- Preserve weekly sheet naming support:
  - `Weekly Plan (M/D/YYYY)`
  - `(Weekly Plan) M/D/YYYY`
- Preserve 8-column sheet schema lock (`A:H`)
- Preserve canonical logging format: `performance | RPE x | Notes: ...`
