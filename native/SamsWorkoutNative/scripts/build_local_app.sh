#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="SamsWorkoutNative"
BUNDLE_NAME="$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
BUNDLE_DIR="$DIST_DIR/$BUNDLE_NAME"
MACOS_DIR="$BUNDLE_DIR/Contents/MacOS"
RESOURCES_DIR="$BUNDLE_DIR/Contents/Resources"
PLIST_PATH="$BUNDLE_DIR/Contents/Info.plist"
BIN_PATH="$ROOT_DIR/.build/release/WorkoutDesktopApp"

mkdir -p "$DIST_DIR"
rm -rf "$BUNDLE_DIR"

swift build -c release --product WorkoutDesktopApp

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Copy app icon if present
ICON_SRC="$ROOT_DIR/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"
    echo "Copied app icon to Resources."
fi

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>local.samuellight.samsworkoutnative</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$BUNDLE_DIR"

echo "Built and signed: $BUNDLE_DIR"

# Recreate the Desktop alias so it survives rm -rf rebuilds
DESKTOP="$HOME/Desktop"
ALIAS_NAME="$APP_NAME.app"
osascript <<APPLESCRIPT
tell application "Finder"
    set appFile to POSIX file "$BUNDLE_DIR" as alias
    set destFolder to POSIX file "$DESKTOP" as alias
    -- Remove stale alias if present
    try
        set staleAlias to file "$ALIAS_NAME" of destFolder
        delete staleAlias
    end try
    make alias file to appFile at destFolder
    set name of result to "$ALIAS_NAME"
end tell
APPLESCRIPT

echo "Desktop alias updated: $DESKTOP/$ALIAS_NAME"
echo "Open with: open \"$BUNDLE_DIR\""
