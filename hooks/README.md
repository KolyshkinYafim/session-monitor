# Terminal Claude monitoring (hooks)

Make the Session Monitor island show your **real `claude` CLI sessions** running in any
terminal — no Chat Hub required. This mirrors how Vibe Island works: Claude Code fires hooks,
a small script maps them to the shared JSONL bridge, and the island reacts.

## Install

```bash
./install.sh      # registers the hook globally in ~/.claude/settings.json (backs it up first)
./uninstall.sh    # removes it again (also backs up)
```

Install is **idempotent** and only touches its own hook entries — any other hooks you have
(including Vibe Island's) are left in place. New Claude Code sessions pick it up automatically.

## What it does

`agent-desktop-claude-hook.py` reads the hook JSON on stdin and appends a bridge event:

| Claude Code hook | Bridge event | Island effect |
|------------------|--------------|---------------|
| `SessionStart` | `session.upsert` (idle) | session appears (hidden until active) |
| `UserPromptSubmit` | `session.upsert` (running, title = your prompt) | shows as running |
| `Notification` (permission/input/idle) | `session.question` | waiting — needs you |
| `Stop` | `session.status` waiting_input | badge lights up — your turn |
| `SessionEnd` | `session.ended` (done) | leaves the live list |

Each session carries a `focusApp` (the host terminal, from `$TERM_PROGRAM`), so clicking the
session in the island brings that terminal forward. v1 is monitor-only: you reply in the
terminal, not from the island.

## Guarantees

- **Never writes to stdout** (stdout on `UserPromptSubmit`/`SessionStart` is injected into
  Claude's context — we must not pollute it).
- **Never fails your session** — every error is swallowed and the hook exits 0.
- Only Python 3 standard library; invoked via absolute `/usr/bin/python3`.

## Bridge path

Writes to `~/Library/Application Support/agent-desktop/events.jsonl`
(override with `AGENT_DESKTOP_EVENTS`). Same file the island tails.
