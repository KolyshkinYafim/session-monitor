#!/bin/bash
# Unit-check the Claude hook: every event maps to the events it should, and nothing
# but a permission decision ever reaches stdout. Also covers the two ways this pair can
# hurt a live machine — install.sh rewriting a config it could not parse, and an
# unwritable events.jsonl swallowing the blocking permission round-trip.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$ROOT/hooks"
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
# Turns the harness generates and submits as if the user typed them. Each must keep the card
# moving without renaming it — the shapes below are copied from real ~/.claude transcripts.
run Prompt-TaskNotif '{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp/demo-proj","prompt":"<task-notification>\n<task-id>ad4335ccfe55530e8</task-id>\n<tool-use-id>toolu_01ABC</tool-use-id>\n<status>completed</status>\n<summary>Agent \"Find API Gateway usage\" finished</summary>\n<result>Here is what I found.</result>\n</task-notification>"}'
run Prompt-SlashCmd  '{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp/demo-proj","prompt":"<command-name>/model</command-name>\n            <command-message>model</command-message>\n            <command-args></command-args>"}'
run Prompt-LocalOut  '{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp/demo-proj","prompt":"<local-command-stdout>Set model to claude-opus-5</local-command-stdout>"}'
run Prompt-Reminder  '{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp/demo-proj","prompt":"<system-reminder>Your todo list has changed. DO NOT mention this explicitly.</system-reminder>"}'
# A block that opens and never closes: everything after it is still the harness talking.
run Prompt-Truncated '{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp/demo-proj","prompt":"<task-notification>\n<task-id>ad4335ccfe55530e8</task-id>\n<summ"}'
# IDE context is a *prefix* to a real prompt, so the typed half still has to win the title.
run Prompt-IdeCtx    '{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp/demo-proj","prompt":"<ide_opened_file>The user opened the file /tmp/demo-proj/src/api.ts in the IDE. This may or may not be related to the current task.</ide_opened_file>\nwhere is our ProxyProviderType?"}'
# The reason this is an allowlist and not \"starts with a tag\": pasted markup is a real prompt.
run Prompt-Markup    '{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp/demo-proj","prompt":"<div class=\"card\"><span>hi</span></div> why does this overflow?"}'
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
echo "=== harness-generated prompts never take over the card title ==="
/usr/bin/python3 - "$OUT" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
bad = 0
def check(label, cond):
    global bad
    print(("  ✓ " if cond else "  ✗ ") + label)
    if not cond:
        bad += 1

titles = [r["session"]["title"] for r in rows if r["type"] == "session.upsert"]
HARNESS = ("<task-notification", "<command-name", "<local-command", "<system-reminder",
           "<scheduled-task", "<ide_opened_file", "<ide_selection")
check("no card title is raw harness markup",
      not any(t.lstrip().startswith(h) for t in titles for h in HARNESS))
check("the typed prompt is still the title", "fix the auth bug in middleware" in titles)
# Five harness turns above; none may mint an upsert, each must still say "running".
running = [i for i, r in enumerate(rows)
           if r["type"] == "session.status" and r["status"] == "running"]
check("every harness turn re-runs the card", len(running) == 5)
check("each one reports activity before the status",
      all(rows[i - 1]["type"] == "session.message" for i in running if i > 0))

previews = [r["preview"] for r in rows if r["type"] == "session.message"]
check("a task-notification card shows its summary",
      'Agent "Find API Gateway usage" finished' in previews)
check("a slash command card shows the command", "/model" in previews)
check("local command output is labelled, not dumped", "Local command" in previews)
check("a system reminder is labelled", "System reminder" in previews)
check("an unclosed harness block is not leaked as activity",
      "Background task finished" in previews)
check("no activity line leaks raw harness markup",
      not any(p.lstrip().startswith(h) for p in previews for h in HARNESS))

# The other half: stripping context must not cost the user their actual words.
check("IDE context is stripped, the typed question becomes the title",
      "where is our ProxyProviderType?" in titles)
check("pasted markup is still treated as a real prompt",
      any(t.startswith("<div class=") for t in titles))
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
echo "=== install.sh offers to disable Vibe Island's hook under a real TTY, and strips it on yes ==="
# The two checks above cover install.sh with no controlling terminal (this test script's own
# stdin isn't a tty), which is the "warn and continue" branch. The offer-to-disable branch
# only runs behind `[ -t 0 ]`, so exercising it needs an actual pseudo-terminal — spawn one
# with Python's pty module and answer the prompt once it appears.
cat > "$FAKE/.claude/settings.json" <<'JSON'
{
  "model": "opus",
  "hooks": {
    "PermissionRequest": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "vibe-island-bridge --source claude", "timeout": 86400 }] }
    ]
  }
}
JSON
HOME="$FAKE" /usr/bin/python3 - "$HOOKS_DIR/install.sh" >"$TMP/install3.log" 2>&1 <<'PY'
import os, pty, select, sys, time
script = sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", script])
    os._exit(1)
os.set_blocking(fd, False)
out = bytearray()
sent = False
deadline = time.time() + 15
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
        if not sent and b"[y/N]" in out:
            os.write(fd, b"y\n")
            sent = True
    wpid, _ = os.waitpid(pid, os.WNOHANG)
    if wpid == pid:
        try:
            while True:
                r2, _, _ = select.select([fd], [], [], 0.1)
                if not r2:
                    break
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                out += chunk
        except OSError:
            pass
        break
sys.stdout.buffer.write(bytes(out))
PY
grep -q "Disable Vibe Island's hook here" "$TMP/install3.log" && pass "prompts to disable Vibe Island under a real TTY" || fail "no interactive prompt appeared under a TTY"
/usr/bin/python3 - "$FAKE/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
groups = d.get("hooks", {}).get("PermissionRequest", [])
cmds = [h.get("command", "") for g in groups for h in g.get("hooks", [])]
ok = not any("vibe-island" in c for c in cmds) and any("agent-desktop-claude-hook" in c for c in cmds)
sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] && pass "answering yes strips Vibe Island's hook and keeps ours" || fail "Vibe Island's hook survived (or ours was dropped) after answering yes"

echo
if [ "$FAILED" -eq 0 ]; then
  echo "✓ all checks passed"
else
  echo "✗ $FAILED check(s) failed"
fi
rm -rf "$TMP"
exit $([ "$FAILED" -eq 0 ] && echo 0 || echo 1)
