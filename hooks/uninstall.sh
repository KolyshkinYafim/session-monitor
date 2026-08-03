#!/usr/bin/env bash
#
# Remove every Agent Desktop integration: Claude Code hooks, Codex hooks, OpenCode plugin.
# Backs up each file first and leaves other tools' entries untouched.
#
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/agent-desktop-claude-hook.py"
PY="$(command -v python3 || true)"

[ -n "$PY" ] || { echo "✗ python3 not found on PATH" >&2; exit 1; }

remove_from() {  # remove_from <settings.json>
  local settings="$1" backup
  [ -f "$settings" ] || { echo "· $settings not found — skipped"; return; }
  backup="$settings.backup-$(date +%Y%m%d-%H%M%S)"
  cp "$settings" "$backup"

  if ! "$PY" - "$settings" <<'PYEOF'
import json, os, sys
settings_path = sys.argv[1]
# JSONC (comments, trailing commas) is legal for the CLIs but not for json.load. Bail out
# loudly rather than reporting a cleanup that never happened.
try:
    with open(settings_path) as f:
        data = json.load(f)
except Exception as err:
    print(f"not parseable as JSON: {err}", file=sys.stderr)
    sys.exit(2)

def is_ours(group):
    if not isinstance(group, dict):
        return False
    for h in group.get("hooks", []):
        if isinstance(h, dict) and "agent-desktop-claude-hook" in str(h.get("command", "")):
            return True
    return False

hooks = data.get("hooks")
if isinstance(hooks, dict):
    for ev in list(hooks.keys()):
        arr = hooks.get(ev)
        if not isinstance(arr, list):
            continue
        kept = [g for g in arr if not is_ours(g)]
        if kept:
            hooks[ev] = kept
        else:
            del hooks[ev]
    if not hooks:
        data.pop("hooks", None)

# Never truncate a live config: a crash mid-dump would leave half a settings.json behind.
tmp = settings_path + ".agent-desktop-tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
try:
    os.chmod(tmp, os.stat(settings_path).st_mode & 0o7777)
except Exception:
    pass
os.replace(tmp, settings_path)
PYEOF
  then
    echo "✗ $settings left untouched — remove the hook entries by hand" >&2
    rm -f "$backup"
    return
  fi

  echo "✓ cleaned $settings"
  echo "    backup: $backup"
}

remove_from "$HOME/.claude/settings.json"
remove_from "$HOME/.codex/hooks.json"

# Grok keeps each hook set in its own file, so ours goes away whole.
GROK_HOOKS="$HOME/.grok/hooks/agent-desktop.json"
if [ -f "$GROK_HOOKS" ]; then
  rm -f "$GROK_HOOKS"
  echo "✓ removed $GROK_HOOKS"
else
  echo "· grok hooks not installed — skipped"
fi

PLUGIN="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/plugins/agent-desktop.js"
if [ -f "$PLUGIN" ]; then
  rm -f "$PLUGIN"
  echo "✓ removed $PLUGIN"
else
  echo "· OpenCode plugin not installed — skipped"
fi

echo
echo "✓ Uninstalled Agent Desktop integrations"
