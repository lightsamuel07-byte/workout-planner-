# Swift Rewrite Parity Matrix

Date: 2026-02-22

## Feature Parity Checklist

- [x] Access control (local app lock + secure secrets)
- [x] Navigation shell parity
- [x] Generate plan workflow parity
- [x] Plan archival behavior parity (local + Sheets tab)
- [x] View plan local/sheets fallback parity
- [x] Workout logger parity (Column H format)
- [x] SQLite sync parity via GRDB
- [x] Progress analytics parity
- [x] Weekly review parity
- [x] Exercise history parity
- [x] DB status parity
- [ ] CLI-equivalent debug utilities where needed

## Hard Rules Parity

- [x] 8-column schema (`A:H`) lock
- [x] Weekly tab naming dual-pattern support
- [x] Log format: `performance | RPE x | Notes: ...`
- [x] Fort parser section handling and noise filtering
- [x] Validator constraints (ranges, DB parity, grip rotation, hold lock)

## Test Parity

- [x] Golden fixtures for core domain logic
- [x] Integration tests for Sheets read/write
- [x] Persistence migration and sync tests

## Notes

- Phases 2-5 module deliverables are implemented and validated in SwiftPM.
- Local app lock flow implemented in native UI (`SetupFlowView` + `UnlockView`) with persisted local config.
- Local signed app packaging script implemented:
  - `native/SamsWorkoutNative/scripts/build_local_app.sh`
  - output artifact: `native/SamsWorkoutNative/dist/SamsWorkoutNative.app`
- Live runtime gateway now wires end-to-end workflows:
  - Anthropic generation + validation/fidelity summary
  - local markdown save with archive-before-overwrite
  - Google Sheets tab archive + rewrite and logger Column H updates
  - View Plan local-first with Sheets fallback
  - local GRDB-backed progress, weekly review, exercise history, DB status
- OAuth token reliability hardened:
  - automatic access-token refresh from OAuth `token.json` when near expiry
  - refresh token exchange + token file write-back support in `AuthSessionManager`
- Anthropic prompt parity improved:
  - richer hard-rule prompt aligned with Python track guardrails
  - progression directives from prior supplemental logs injected into prompt
  - deterministic repair sequence + correction loop (up to 2 attempts) with validation/fidelity feedback
- `WorkoutDesktopApp` now launches as a real native macOS window from `main.swift` (AppKit + SwiftUI hosting), and smoke launch of built `.app` was verified.
