#!/usr/bin/env bash
#
# Build SessionMonitor (Release), install it to /Applications, and start it at login.
# Re-runnable: rebuilds and replaces the installed copy. Undo with uninstall-app.sh.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/SessionMonitor/SessionMonitor.xcodeproj"
BUILD_DIR="$ROOT/SessionMonitor/build/Release"
APP="$BUILD_DIR/Build/Products/Release/SessionMonitor.app"
DST="/Applications/SessionMonitor.app"
PLIST_SRC="$ROOT/packaging/com.agentdesktop.SessionMonitor.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.agentdesktop.SessionMonitor.plist"

echo "→ Building Release…"
xcodebuild -project "$PROJECT" -scheme SessionMonitor -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build >/dev/null

echo "→ Installing to $DST…"
pkill -f "SessionMonitor.app/Contents/MacOS/SessionMonitor" 2>/dev/null || true
sleep 1
rm -rf "$DST"
cp -R "$APP" "$DST"

echo "→ Enabling launch at login…"
mkdir -p "$HOME/Library/LaunchAgents"
cp "$PLIST_SRC" "$PLIST_DST"
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"

echo "✓ Installed and started. The island runs now and at every login."
echo "  Undo: $ROOT/packaging/uninstall-app.sh"
