#!/usr/bin/env bash
#
# Stop SessionMonitor, remove it from /Applications, and disable launch at login.
#
set -euo pipefail

PLIST_DST="$HOME/Library/LaunchAgents/com.agentdesktop.SessionMonitor.plist"
DST="/Applications/SessionMonitor.app"

launchctl unload "$PLIST_DST" 2>/dev/null || true
rm -f "$PLIST_DST"
pkill -f "SessionMonitor.app/Contents/MacOS/SessionMonitor" 2>/dev/null || true
rm -rf "$DST"
echo "✓ Uninstalled SessionMonitor and disabled launch at login."
echo "  (The Claude Code hook is separate — remove it with hooks/uninstall.sh if you want.)"
