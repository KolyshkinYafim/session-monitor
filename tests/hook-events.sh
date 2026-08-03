#!/bin/bash
# Unit-check the Claude hook: every event maps to the events it should, and nothing
# but a permission decision ever reaches stdout. Also covers the two ways this pair can
# hurt a live machine — install.sh rewriting a config it could not parse, and an
# unwritable events.jsonl swallowing the blocking permission round-trip.
set -u
HOOKS_DIR=/Users/yafimkolyshkin/Desktop/agent-desktop-suite/session-monitor/hooks
HOOK="$HOOKS_DIR/agent-desktop-claude-hook.py"
TMP=$(mktemp -d)
OUT="$TMP/events.jsonl"
export AGENT_DESKTOP_EVENTS="$OUT"
export AGENT_DESKTOP_SOCKET="/nonexistent/monitor.sock"   # force fail-open path
export TERM_PROGRAM=iTerm.app ITERM_SESSION_ID="w0t0p0:ABC-123"
export KITTY_WINDOW_ID=7 TMUX_PANE=%3 TMUX=/private/tmp/tmux-501/default,999,0

FAILED=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILED=$((FAILED + 1)); }

run() {  # run <label> <json>
  local label="$1" json="$2"
  local stdout code
  stdout=$(printf '%s' "$json" | /usr/bin/python3 "$HOOK" 2>"$TMP/hookerr.txt")
  code=$?
  printf '%-18s exit=%s stdout=%s\n' "$label" "$code" "${stdout:-<empty>}"
  [ "$code" = 0 ] || fail "$label exited $code"
  # stdout on anything but PermissionRequest is injected into the agent's context.
  [ -z "$stdout" ] || fail "$label wrote to stdout"
  [ -s "$TMP/hookerr.txt" ] && { echo "   stderr:"; cat "$TMP/hookerr.txt"; fail "$label wrote to stderr"; }
  return 0
}

run SessionStart     '{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/tmp/demo-proj","model":"claude-opus-5","source":"startup"}'
run UserPrompt       '{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp/demo-proj","prompt":"fix the auth bug in middleware"}'
run PostToolUse-Read '{"hook_event_name":"PostToolUse","session_id":"s1","cwd":"/tmp/demo-proj","tool_name":"Read","tool_input":{"file_path":"/tmp/demo-proj/prisma/schema.prisma"}}'
run PostToolUse-Bash '{"hook_event_name":"PostToolUse","session_id":"s1","cwd":"/tmp/demo-proj","tool_name":"Bash","tool_input":{"command":"npm test -- --watch=false"}}'
run PostToolUse-Edit '{"hook_event_name":"PostToolUse","session_id":"s1","cwd":"/tmp/demo-proj","tool_name":"Edit","tool_input":{"file_path":"/tmp/demo-proj/src/db/queries.ts","old_string":"a\nb\nc","new_string":"a\nb\nc\nd\ne"}}'
run Notification     '{"hook_event_name":"Notification","session_id":"s1","notification_type":"idle_prompt","message":"Claude is waiting for your input"}'
run PermissionReq    '{"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/tmp/demo-proj","tool_name":"Bash","tool_input":{"command":"rm -rf build"},"tool_use_id":"toolu_01ABC"}'
run Perm-AskUser     '{"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/tmp/demo-proj","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which database should the seed target?","header":"DB"}]}}'
run Perm-ExitPlan    '{"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/tmp/demo-proj","tool_name":"ExitPlanMode","tool_input":{"plan":"## Plan\nRewrite the token refresh path"}}'
run Stop             '{"hook_event_name":"Stop","session_id":"s1","cwd":"/tmp/demo-proj","last_assistant_message":"Fixed the expiry check in middleware.ts"}'
run SessionEnd       '{"hook_event_name":"SessionEnd","session_id":"s1","cwd":"/tmp/demo-proj","reason":"exit"}'
run Garbage          'not json at all'
run Empty            ''

echo
echo "=== events.jsonl ==="
/usr/bin/python3 - "$OUT" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    o = json.loads(line)
    t = o["type"]
    if t == "session.upsert":
        s = o["session"]
        print(f'  upsert    {s["status"]:<13} title={s["title"][:34]!r} activity={s.get("lastActivity","")!r} termIds={sorted(s.get("termIds",{}))}')
    elif t == "session.message":
        print(f'  message   role={o["role"]:<9} preview={o["preview"]!r}')
    elif t == "session.permission":
        print(f'  permission requestId={o["requestId"]!r} summary={o["summary"]!r}')
    elif t == "session.question":
        print(f'  question  prompt={o["prompt"]!r}')
    else:
        print(f'  {t:<9} {json.dumps({k:v for k,v in o.items() if k not in ("type","ts")})}')
PY

echo
echo "=== event contract ==="
/usr/bin/python3 - "$OUT" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
bad = 0
def check(label, cond):
    global bad
    print(("  ✓ " if cond else "  ✗ ") + label)
    if not cond:
        bad += 1

# The consumer treats any message as fresh activity and pulls an idle card back to running,
# so a finished turn must end on the status line, not on the banner.
idx_msg = next(i for i, r in enumerate(rows) if r["type"] == "session.message" and r["role"] == "assistant")
idx_idle = next(i for i, r in enumerate(rows) if r["type"] == "session.status" and r["status"] == "idle")
check("Stop emits the banner before the idle status", idx_msg < idx_idle)
check("idle status is the last word of the turn",
      all(r["type"] != "session.message" for r in rows[idx_idle + 1:]))

perms = [r for r in rows if r["type"] == "session.permission"]
by_summary = {r["summary"] for r in perms}
check("AskUserQuestion card shows the question",
      any(s.startswith("AskUserQuestion(Which database") for s in by_summary))
check("ExitPlanMode card shows the plan", any(s.startswith("ExitPlanMode(") for s in by_summary))
check("no permission card degrades to 'Allow <tool>?'",
      not any(s.startswith("Allow ") for s in by_summary))
check("Notification becomes a question", any(r["type"] == "session.question" for r in rows))
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || FAILED=$((FAILED + 1))

echo
echo "=== unwritable events.jsonl still reaches the permission socket ==="
SOCK="$TMP/monitor.sock"
/usr/bin/python3 - "$SOCK" <<'PY' &
import socket, sys
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(sys.argv[1])
srv.listen(4)
srv.settimeout(30)
try:
    while True:
        conn, _ = srv.accept()
        conn.recv(1 << 16)
        conn.sendall(b'{"decision":{"behavior":"allow"}}\n')
        conn.close()
except Exception:
    pass
PY
STUB=$!
for i in $(seq 1 25); do [ -S "$SOCK" ] && break; sleep 0.2; done
PERM='{"hook_event_name":"PermissionRequest","session_id":"s2","cwd":"/tmp/demo-proj","tool_name":"Bash","tool_input":{"command":"ls"}}'
DECISION=$(printf '%s' "$PERM" | AGENT_DESKTOP_SOCKET="$SOCK" /usr/bin/python3 "$HOOK")
case "$DECISION" in *'"allow"'*) pass "writable events file → decision returned";; *) fail "no decision with a writable events file: ${DECISION:-<empty>}";; esac
BLOCKED="$TMP/blocked/events.jsonl"
mkdir -p "$TMP/blocked" && : > "$BLOCKED" && chmod 000 "$BLOCKED"
DECISION=$(printf '%s' "$PERM" | AGENT_DESKTOP_EVENTS="$BLOCKED" AGENT_DESKTOP_SOCKET="$SOCK" /usr/bin/python3 "$HOOK")
case "$DECISION" in *'"allow"'*) pass "unwritable events file → decision still returned";; *) fail "unwritable events file swallowed the decision: ${DECISION:-<empty>}";; esac
chmod 644 "$BLOCKED"
# Reap inside the group, or bash prints its own "Terminated" notice into the report.
{ kill "$STUB"; wait "$STUB"; } 2>/dev/null

echo
echo "=== install.sh never rewrites a config it could not parse ==="
FAKE="$TMP/home"
mkdir -p "$FAKE/.claude"
# Legal JSONC for the CLIs, invalid JSON for us — the case that used to wipe the file.
printf '{\n  // pick the model here\n  "model": "opus"\n}\n' > "$FAKE/.claude/settings.json"
cp "$FAKE/.claude/settings.json" "$TMP/settings.before"
HOME="$FAKE" "$HOOKS_DIR/install.sh" >"$TMP/install.log" 2>&1
[ $? -ne 0 ] && pass "install.sh exits non-zero" || fail "install.sh reported success on an unparseable config"
cmp -s "$TMP/settings.before" "$FAKE/.claude/settings.json" && pass "settings.json byte-identical" || fail "settings.json was rewritten"

# The other half of the promise: a parseable config keeps every foreign key and hook.
cat > "$FAKE/.claude/settings.json" <<'JSON'
{
  "model": "opus",
  "permissions": { "allow": ["Bash(ls:*)"] },
  "hooks": {
    "PermissionRequest": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "vibe-island-bridge --source claude", "timeout": 86400 }] }
    ]
  }
}
JSON
HOME="$FAKE" "$HOOKS_DIR/install.sh" >"$TMP/install2.log" 2>&1
grep -q "another blocking PermissionRequest hook" "$TMP/install2.log" && pass "warns about the competing blocking hook" || fail "no warning about the competing blocking hook"
/usr/bin/python3 - "$FAKE/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
groups = d.get("hooks", {}).get("PermissionRequest", [])
cmds = [h.get("command", "") for g in groups for h in g.get("hooks", [])]
ok = d.get("model") == "opus" and d.get("permissions", {}).get("allow") == ["Bash(ls:*)"]
ok = ok and any("vibe-island" in c for c in cmds) and any("agent-desktop-claude-hook" in c for c in cmds)
sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] && pass "unrelated settings and Vibe Island's hook survive" || fail "install.sh dropped foreign settings or hooks"

echo
if [ "$FAILED" -eq 0 ]; then
  echo "✓ all checks passed"
else
  echo "✗ $FAILED check(s) failed"
fi
rm -rf "$TMP"
exit $([ "$FAILED" -eq 0 ] && echo 0 || echo 1)
