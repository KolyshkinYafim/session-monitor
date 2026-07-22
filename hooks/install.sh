#!/usr/bin/env bash
#
# Register the Agent Desktop Claude Code hook globally in ~/.claude/settings.json so the
# Session Monitor island can see terminal `claude` sessions. Idempotent + backs up settings.
# Undo with ./uninstall.sh.
#
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/agent-desktop-claude-hook.py"
SETTINGS="$HOME/.claude/settings.json"
PY="$(command -v python3 || true)"

[ -f "$HOOK" ] || { echo "✗ hook script not found: $HOOK" >&2; exit 1; }
[ -n "$PY" ] || { echo "✗ python3 not found on PATH" >&2; exit 1; }
chmod +x "$HOOK"

mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
BACKUP="$SETTINGS.backup-$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$BACKUP"

CMD="$PY $HOOK"
"$PY" - "$SETTINGS" "$CMD" <<'PYEOF'
import json, sys
settings_path, cmd = sys.argv[1], sys.argv[2]
try:
    with open(settings_path) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}
hooks = data.setdefault("hooks", {})
events = ["SessionStart", "UserPromptSubmit", "Notification", "Stop", "SessionEnd"]
entry = {"hooks": [{"type": "command", "command": cmd}]}
for ev in events:
    arr = hooks.get(ev)
    if not isinstance(arr, list):
        arr = []
    # Drop any prior copy of OUR hook (idempotent), keep the user's other hooks untouched.
    arr = [g for g in arr if not (isinstance(g, dict) and any(
        isinstance(h, dict) and h.get("command") == cmd for h in g.get("hooks", [])))]
    arr.append(json.loads(json.dumps(entry)))
    hooks[ev] = arr
with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("  events: " + ", ".join(events))
PYEOF

echo "✓ Installed Agent Desktop hook"
echo "  command : $CMD"
echo "  settings: $SETTINGS"
echo "  backup  : $BACKUP"
echo "  New Claude Code sessions will now appear in the Session Monitor island."
echo "  Undo: $HOOK_DIR/uninstall.sh"
