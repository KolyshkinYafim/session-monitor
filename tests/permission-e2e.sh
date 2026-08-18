#!/bin/bash
# End-to-end checks for the permission socket: allow, deny, hook death, second instance.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/agent-desktop-claude-hook.py"
# Most recently built Debug binary, whichever DerivedData tree it lives in.
BIN=$(ls -t ~/Library/Developer/Xcode/DerivedData/SessionMonitor-*/Build/Products/Debug/SessionMonitor.app/Contents/MacOS/SessionMonitor 2>/dev/null | head -1)
if [ -z "$BIN" ]; then
  BUILT=$(xcodebuild -project "$ROOT/SessionMonitor/SessionMonitor.xcodeproj" -scheme SessionMonitor -configuration Debug -showBuildSettings 2>/dev/null \
    | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' | head -1)
  [ -n "$BUILT" ] && BIN="$BUILT/SessionMonitor.app/Contents/MacOS/SessionMonitor"
fi
[ -x "$BIN" ] || { echo "✗ no Debug SessionMonitor binary found — build the app first"; exit 1; }
SOCK="$HOME/Library/Application Support/agent-desktop/monitor.sock"

start_app() { # start_app <auto-approve value>
  pkill -f 'SessionMonitor.app/Contents/MacOS'; sleep 1
  # A killed app may leave the socket file behind — clear it so waiting for it to
  # reappear actually means "the new instance is listening".
  rm -f "$SOCK" /tmp/sm.log
  nohup env SESSION_MONITOR_DEBUG=1 SESSION_MONITOR_AUTO_APPROVE="$1" "$BIN" >/tmp/sm.log 2>&1 &
  disown
  for i in $(seq 1 20); do [ -S "$SOCK" ] && return 0; sleep 0.5; done
  echo "✗ socket never appeared"; return 1
}

request() { # request <session> <tool_use_id> <json tool_input>
  printf '{"hook_event_name":"PermissionRequest","session_id":"%s","cwd":"/tmp/demo-proj","tool_name":"Bash","tool_input":%s,"tool_use_id":"%s"}' "$1" "$3" "$2" \
    | /usr/bin/python3 "$HOOK"
}

echo "=== 1. Allow ==="
start_app allow || exit 1
OUT=$(request allow-1 toolu_A1 '{"command":"npm test"}')
echo "$OUT" | grep -q '"behavior": "allow"' && echo "✓ hook received allow" || echo "✗ got: $OUT"

echo
echo "=== 2. Deny ==="
start_app deny || exit 1
OUT=$(request deny-1 toolu_D1 '{"command":"rm -rf /"}')
echo "$OUT" | grep -q '"behavior": "deny"' && echo "✓ hook received deny" || echo "✗ got: $OUT"

echo
echo "=== 3. Hook dies while waiting (no app crash, card released) ==="
start_app "" || exit 1
( request killme toolu_K1 '{"command":"sleep 999"}' >/tmp/killme.out 2>&1 ) &
# Wait until the hook is actually connected before killing it.
for i in $(seq 1 20); do grep -q 'reader started' /tmp/sm.log && break; sleep 0.5; done
grep -q 'reader started' /tmp/sm.log || echo "   (hook never connected)"
# $! is the subshell, not python — kill the hook process itself, or it keeps waiting.
pkill -9 -f agent-desktop-claude-hook
pgrep -f 'SessionMonitor.app/Contents/MacOS' >/dev/null && echo "✓ app survived hook kill" || echo "✗ app died"
# The reader thread traces asynchronously — give it a moment before judging.
for i in $(seq 1 10); do grep -q 'eof on fd' /tmp/sm.log && break; sleep 0.5; done
grep -q 'eof on fd' /tmp/sm.log && echo "✓ server saw EOF and released the request" || { echo "✗ no EOF handling in trace"; echo "   trace was:"; sed 's/^/   /' /tmp/sm.log; }

echo
echo "=== 4. App down → fail open (Claude keeps its own prompt) ==="
pkill -f 'SessionMonitor.app/Contents/MacOS'; sleep 1
OUT=$(request nomonitor toolu_N1 '{"command":"ls"}')
[ -z "$OUT" ] && echo "✓ no stdout when the monitor is gone" || echo "✗ unexpected stdout: $OUT"

echo
echo "=== 5. Second instance refuses to steal the socket ==="
start_app allow || exit 1
FIRST=$(pgrep -f 'SessionMonitor.app/Contents/MacOS' | head -1)
nohup env SESSION_MONITOR_DEBUG=1 "$BIN" >/tmp/sm2.log 2>&1 & disown
sleep 2
COUNT=$(pgrep -f 'SessionMonitor.app/Contents/MacOS' | wc -l | tr -d ' ')
[ "$COUNT" = "1" ] && echo "✓ only one instance alive (pid $FIRST)" || echo "✗ $COUNT instances running"
OUT=$(request after-dup toolu_S1 '{"command":"npm run build"}')
echo "$OUT" | grep -q '"behavior": "allow"' && echo "✓ socket still served by the first instance" || echo "✗ socket broken after duplicate launch: $OUT"

pkill -f 'SessionMonitor.app/Contents/MacOS'
echo
echo "done"
