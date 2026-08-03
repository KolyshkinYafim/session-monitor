# Chat Hub bridge

Session Monitor **consumes** `SessionEvent` JSONL produced by Chat Hub.

## Path

```
~/Library/Application Support/agent-desktop/events.jsonl
```

Override with env `AGENT_DESKTOP_EVENTS`.

Matches Chat Hub `docs/bridge.md`.

## Behavior

1. Ensure file exists (create empty if missing).
2. Replay existing lines on start (`running` / `waiting_input` coerced to `idle` during replay).
3. Live-tail via FS events + short poll.
4. Forward validated events into `SessionStore`.

## Format

Append-only JSONL, one event per line. See Chat Hub bridge doc for examples.

## Rotation

Producers (hooks, Chat Hub) **only append**, with a single `O_APPEND` write — atomic
against every other appender, so appending needs no lock.

Trimming does. Session Monitor is the primary trimmer: past 2 MB it rewrites the file to
its last 1500 lines **in place**, keeping the same inode so an `O_APPEND` writer never
loses a line, then re-anchors its own read offset. Chat Hub has the same trimmer with a
far higher cap (8 MB), so it only ever fires when the island is not running.

### The lock

Read-modify-write is the one operation that can destroy someone else's append, so a
trimmer must hold the lock — and **all three languages must use the same primitive**.

`flock(2)` cannot be that primitive: Node exposes no `flock`, and
`fs.constants.O_EXLOCK` is `undefined` on the Node builds Chat Hub ships against. So a
Swift-only `flock` silently excluded nobody, and a trim could eat Hub appends.

The shared primitive is an **exclusive create of a sibling lock file**:

| | path |
|---|---|
| lock file | `<events.jsonl>.lock` |

- **acquire** — `O_CREAT \| O_EXCL` on that path. Swift: `open(..., O_CREAT\|O_EXCL\|O_WRONLY, 0644)`. Node: `fs.open(path, "wx")`. Python: `os.open(..., os.O_CREAT\|os.O_EXCL\|os.O_WRONLY)`.
- **retry** — every 25 ms, for at most **1.5 s**.
- **stale** — a lock file whose mtime is older than **5 s** is broken (a process was killed mid-trim; without this the bridge would wedge forever).
- **release** — unlink.

Two different failure rules, on purpose:

- **Writers fail open.** If the lock cannot be taken, append anyway. Losing a status line
  to a concurrent trim is cosmetic; blocking an agent's turn behind a stale lock is not.
- **Trimmers fail closed.** If the lock cannot be taken, skip the rewrite and retry later.
  An oversized file is harmless; a trim that eats someone's append is not.

Implementations: `SessionMonitor/Services/ChatHubBridge.swift` (`acquireBridgeLock`),
`chat-hub/src/main/bridge-lock.ts` (`withBridgeLock`). Covered by
`chat-hub/tests/bridge-lock.test.ts`. **Change all sides together or not at all.**

## Sources

| Agent | Mechanism | Config |
|-------|-----------|--------|
| Chat Hub | JSONL bridge | `events.jsonl` |
| Claude Code | hooks | `~/.claude/settings.json` |
| Codex CLI | hooks (same protocol as Claude) | `~/.codex/hooks.json` |
| Grok CLI | hooks, no permission event | `~/.grok/hooks/agent-desktop.json` |
| OpenCode | JS plugin → socket | `~/.config/opencode/plugins/agent-desktop.js` |

Session ids are namespaced per agent (`claude-…`, `codex-…`, `grok-…`, `opencode-…`) so two
agents in one repo never share a card.

## Permission socket (blocking, terminal agents)

```
~/Library/Application Support/agent-desktop/monitor.sock
```

Override with `AGENT_DESKTOP_SOCKET`. One connection per hook invocation, NDJSON in both
directions:

```jsonc
// hook → monitor
{"v":1,"source":"claude","event":"PermissionRequest","sessionId":"…","requestId":"toolu_…","summary":"Bash(npm test)","payload":{…raw hook JSON…}}
// monitor → hook, whenever the user decides (hook is registered with timeout 86400)
{"decision":{"behavior":"allow"}}
```

The socket also accepts plain `SessionEvent` lines — the same shape as the JSONL bridge —
so a source without a hook protocol (the OpenCode plugin, any future watcher) can push
straight in and gets `{"ok":true}` back:

```json
{"type":"session.upsert","session":{"id":"opencode-abc","provider":"opencode","status":"running","cwd":"/repo"},"ts":1785311320}
```

The hook then prints Claude Code's own contract to stdout and exits 0:

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
```

Fail-open on every edge: no socket, no answer, killed monitor, or a crash all end with the
hook exiting 0 and printing nothing, which leaves Claude's own prompt in charge. If the
hook dies while the monitor holds it, the server sees EOF and clears the card.

Implementation notes that are easy to regress:

- the listening socket is **non-blocking** and accepts in a loop until `EAGAIN` — a blocking
  second `accept()` on the main thread froze the whole app, UI included;
- each connection gets a parked reader thread (a dispatch read source on the accepted
  descriptor never fired) and that thread owns the `close()`;
- `SO_NOSIGPIPE` on accept, so answering a hook that already died can't kill the app;
- one instance only: `monitor.lock` (flock) keeps a second copy from unlinking a live socket.

### Dev switches

| Env | Effect |
|-----|--------|
| `SESSION_MONITOR_DEBUG=1` | Trace the hook conversation to stderr |
| `SESSION_MONITOR_AUTO_APPROVE=allow\|deny` | Answer permissions without a click (E2E tests only) |
| `SESSION_MONITOR_MOCK=1` | Local demo sessions |

## Reverse channel (Monitor → Hub)

```
~/Library/Application Support/agent-desktop/commands.jsonl
```

| Command | Purpose |
|---------|---------|
| `{"type":"session.focus","id":"..."}` | Open / focus chat in Hub |
| `{"type":"session.reply","id":"...","text":"...","requestId":"..."}` | Send answer to waiting agent |

Override with `AGENT_DESKTOP_COMMANDS`.
