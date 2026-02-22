# SamsWorkoutNative

Native Swift rewrite workspace for Samuel's Workout Planner.

## Current Status

- Phases 2-5 implemented with live runtime wiring in `WorkoutDesktopApp`.
- Native app launches a real macOS window (`main.swift` AppKit + SwiftUI host).
- Workflow coverage now includes:
  - plan generation + validation/fidelity summary
  - local plan archival and persistence
  - Google Sheets tab archival/rewrite
  - logger Column H writes + GRDB sync
  - View Plan local-first with Sheets fallback
  - GRDB-backed progress/weekly review/exercise history/status summaries
- OAuth reliability:
  - automatic refresh-token exchange from OAuth token file when access token is expired/near expiry
- Generation reliability:
  - progression directives + deterministic repair/correction loop for stronger parity with Python prompt flow

## Commands

From this folder:

```bash
swift package describe
swift build
swift test
./scripts/build_local_app.sh
```

## Build Artifact

Local signed app output:

```bash
dist/SamsWorkoutNative.app
```

## Toolchain Notes

If global `xcode-select` points to Command Line Tools, run commands with:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

Optional system-wide switch (requires admin):

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```
