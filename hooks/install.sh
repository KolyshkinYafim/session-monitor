#!/usr/bin/env bash
#
# Register the Agent Desktop hook with every supported CLI found on this machine:
#   Claude Code → ~/.claude/settings.json
#   Codex CLI   → ~/.codex/hooks.json
# Idempotent, backs up each file, leaves other tools' hooks (e.g. Vibe Island) alone.
# Undo with ./uninstall.sh.
#
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/agent-desktop-claude-hook.py"
PY="$(command -v python3 || true)"

[ -f "$HOOK" ] || { echo "✗ hook script not found: $HOOK" >&2; exit 1; }
[ -n "$PY" ] || { echo "✗ python3 not found on PATH" >&2; exit 1; }
chmod +x "$HOOK"

# Fail-open: if the hook is missing/unexecutable, exit 0 so the agent continues.
# exec preserves stdout for PermissionRequest decisions.
wrapper_for() {  # wrapper_for <source>
  printf '/bin/sh -c '"'"'if [ -x "%s" ]; then exec "%s" "%s" --source %s; fi; exit 0'"'"'' \
    "$HOOK" "$PY" "$HOOK" "$1"
}

install_into() {  # install_into <settings.json> <source-name> <events csv> <blocking: yes|no>
  local settings="$1" source="$2" events="$3" blocking="$4"
  local dir backup cmd
  dir="$(dirname "$settings")"
  mkdir -p "$dir"
  [ -f "$settings" ] || echo '{}' > "$settings"
  backup="$settings.backup-$(date +%Y%m%d-%H%M%S)"
  cp "$settings" "$backup"
  cmd="$(wrapper_for "$source")"

  if ! AD_EVENTS="$events" AD_BLOCKING="$blocking" "$PY" - "$settings" "$cmd" <<'PYEOF'
import json, os, sys
settings_path, cmd = sys.argv[1], sys.argv[2]
try:
    with open(settings_path) as f:
        raw = f.read()
except Exception as err:
    print(f"cannot read: {err}", file=sys.stderr)
    sys.exit(2)
# The CLIs parse these files as JSONC, json.loads does not: a `//` comment or a trailing
# comma used to land here as "empty config" and we rewrote the file with only our hooks,
# wiping model/permissions/env and every other tool's hooks. Refuse instead.
data = {}
if raw.strip():
    try:
        data = json.loads(raw)
    except Exception as err:
        print(f"not parseable as JSON: {err}", file=sys.stderr)
        sys.exit(2)
    if not isinstance(data, dict):
        print("top level is not an object", file=sys.stderr)
        sys.exit(2)
hooks = data.setdefault("hooks", {})
if not isinstance(hooks, dict):
    print("`hooks` is not an object", file=sys.stderr)
    sys.exit(2)

# Our marker — drop any prior Agent Desktop command (path or --source may have moved).
def is_ours(group):
    if not isinstance(group, dict):
        return False
    for h in group.get("hooks", []):
        if not isinstance(h, dict):
            continue
        c = h.get("command") or ""
        if "agent-desktop-claude-hook" in c or "agent-desktop-suite/session-monitor/hooks" in c:
            return True
    return False

# Fire-and-forget events for this CLI (they don't all support the same set).
fast_events = [e for e in os.environ.get("AD_EVENTS", "").split(",") if e]
# Blocking permission — long timeout so the island can wait for the user.
slow_events = {"PermissionRequest": 86400} if os.environ.get("AD_BLOCKING") == "yes" else {}

def put(ev, timeout=None):
    arr = hooks.get(ev)
    if not isinstance(arr, list):
        arr = []
    arr = [g for g in arr if not is_ours(g)]
    entry = {"hooks": [{"type": "command", "command": cmd}]}
    if timeout is not None:
        entry["hooks"][0]["timeout"] = timeout
        # Some builds read the timeout on the matcher group.
        entry["timeout"] = timeout
    arr.append(entry)
    hooks[ev] = arr

# Two blocking PermissionRequest hooks race: the CLI takes whichever decision arrives first
# and aborts the loser, so both islands prompt and one of the answers is thrown away.
if slow_events:
    rival = [g for g in (hooks.get("PermissionRequest") or []) if not is_ours(g)]
    if rival:
        print("! another blocking PermissionRequest hook is registered here — both it and "
              "the island will prompt, and the first answer wins", file=sys.stderr)

for ev in fast_events:
    put(ev)
for ev, timeout in slow_events.items():
    put(ev, timeout=timeout)

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
    echo "✗ $source → $settings left untouched — fix the file (comments and trailing commas are not JSON) and re-run" >&2
    rm -f "$backup"
    return 1
  fi

  echo "✓ $source → $settings"
  echo "    backup: $backup"
}

CLAUDE_EVENTS="SessionStart,UserPromptSubmit,Notification,Stop,StopFailure,SessionEnd,PostToolUse"
CODEX_EVENTS="SessionStart,UserPromptSubmit,Stop,SessionEnd,PostToolUse"
# Grok has no PermissionRequest (it approves in-CLI) but does report failed tools.
GROK_EVENTS="SessionStart,UserPromptSubmit,Notification,Stop,SessionEnd,PostToolUse,PostToolUseFailure"

installed=0
skipped=0

# One unparseable config must not abort the others, hence the explicit branches under `set -e`.
try_install() {  # try_install <settings.json> <source-name> <events csv> <blocking>
  if install_into "$@"; then
    installed=$((installed + 1))
  else
    skipped=$((skipped + 1))
  fi
}

# Claude Code — settings.json also holds unrelated config, so it always exists in practice.
try_install "$HOME/.claude/settings.json" claude "$CLAUDE_EVENTS" yes

# Codex CLI — same hook protocol, separate config file. Only if Codex is actually present.
if [ -d "$HOME/.codex" ] || command -v codex >/dev/null 2>&1; then
  try_install "$HOME/.codex/hooks.json" codex "$CODEX_EVENTS" yes
else
  echo "· codex not found (~/.codex missing) — skipped"
fi

# Grok CLI — hooks live as separate files under ~/.grok/hooks/.
if [ -d "$HOME/.grok" ] || command -v grok >/dev/null 2>&1; then
  try_install "$HOME/.grok/hooks/agent-desktop.json" grok "$GROK_EVENTS" no
else
  echo "· grok not found (~/.grok missing) — skipped"
fi

"$HOOK_DIR/install-opencode-plugin.sh" || true

echo
echo "✓ Installed Agent Desktop hooks into $installed CLI config(s)"
echo "  events  : session start/end, prompts, tool use, stop (per-CLI subset)"
echo "  blocking: PermissionRequest (timeout 86400s) → Allow/Deny in the island — Claude & Codex"
echo "  socket  : ~/Library/Application Support/agent-desktop/monitor.sock"
echo "  OpenCode: run $HOOK_DIR/install-opencode-plugin.sh"
echo "  Undo    : $HOOK_DIR/uninstall.sh"

# Non-zero so a wrapper/CI notices that a config was left alone.
[ "$skipped" -eq 0 ] || { echo; echo "✗ $skipped config(s) skipped — see the errors above"; exit 1; }
