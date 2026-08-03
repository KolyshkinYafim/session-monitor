#!/usr/bin/env bash
#
# Install the Agent Desktop OpenCode plugin into ~/.config/opencode/plugins/.
# OpenCode loads every JS file in that directory at startup, so a copy is all it takes.
# Re-runnable; keeps a backup of any previous copy. Undo: ./uninstall.sh
#
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HOOK_DIR/opencode/agent-desktop.js"
DEST_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/plugins"
DEST="$DEST_DIR/agent-desktop.js"

[ -f "$SRC" ] || { echo "✗ plugin source not found: $SRC" >&2; exit 1; }

if ! command -v opencode >/dev/null 2>&1 && [ ! -d "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}" ]; then
  echo "· opencode not found — skipped (install OpenCode first)"
  exit 0
fi

mkdir -p "$DEST_DIR"
if [ -f "$DEST" ]; then
  cp "$DEST" "$DEST.backup-$(date +%Y%m%d-%H%M%S)"
fi
cp "$SRC" "$DEST"

echo "✓ OpenCode plugin installed"
echo "  $DEST"
echo "  Restart any running \`opencode\` session for it to load."
echo "  Undo: rm \"$DEST\""
