#!/usr/bin/env bash
#
# Remove the Agent Desktop Claude Code hook from ~/.claude/settings.json.
# Backs up settings first and leaves any other hooks untouched.
#
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/agent-desktop-claude-hook.py"
SETTINGS="$HOME/.claude/settings.json"
PY="$(command -v python3 || true)"

[ -f "$SETTINGS" ] || { echo "nothing to do: $SETTINGS not found"; exit 0; }
[ -n "$PY" ] || { echo "✗ python3 not found on PATH" >&2; exit 1; }

BACKUP="$SETTINGS.backup-$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$BACKUP"

"$PY" - "$SETTINGS" "$HOOK" <<'PYEOF'
import json, sys
settings_path, hook_path = sys.argv[1], sys.argv[2]
try:
    with open(settings_path) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
hooks = data.get("hooks")
if isinstance(hooks, dict):
    for ev in list(hooks.keys()):
        arr = hooks.get(ev)
        if not isinstance(arr, list):
            continue
        # Drop groups whose command references our hook script; keep everything else.
        arr = [g for g in arr if not (isinstance(g, dict) and any(
            isinstance(h, dict) and hook_path in str(h.get("command", "")) for h in g.get("hooks", [])))]
        if arr:
            hooks[ev] = arr
        else:
            del hooks[ev]
    if not hooks:
        data.pop("hooks", None)
with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("  removed Agent Desktop hook entries")
PYEOF

echo "✓ Uninstalled. Backup: $BACKUP"
