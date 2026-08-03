# Terminal agent monitoring (hooks + plugin)

Make the Session Monitor island show your **real terminal agent sessions** — no Chat Hub
required. Claude Code, Codex and Grok all fire hooks; OpenCode loads a plugin. Everything
lands in the same island.

## Install

```bash
./install.sh                    # every CLI found on this machine (backs each config up)
./install-opencode-plugin.sh    # OpenCode only (install.sh runs it too)
./uninstall.sh                  # removes all of it
```

Install is **idempotent** and only touches its own entries — other tools' hooks (including
Vibe Island's) stay in place. New sessions pick it up automatically; restart `opencode` for
the plugin.

A config it cannot parse is left **byte-identical** and reported (the CLIs accept JSONC,
`json.load` does not — comments and trailing commas land here as a parse error, not as an
empty config). Fix the file and re-run. If another blocking `PermissionRequest` hook is
already registered, install warns: both it and the island will prompt and the first answer
wins, so keep only one.

## What gets installed where

| Agent | Config | Blocking approve | Notes |
|-------|--------|------------------|-------|
| Claude Code | `~/.claude/settings.json` | ✅ `PermissionRequest` | Same file as your other settings — only the hooks block is touched |
| Codex CLI | `~/.codex/hooks.json` | ✅ `PermissionRequest` | Identical hook protocol to Claude Code |
| Grok CLI | `~/.grok/hooks/agent-desktop.json` | ❌ | Grok approves in-CLI, so monitoring only. `/hooks-list` inside grok shows whether it loaded |
| OpenCode | `~/.config/opencode/plugins/agent-desktop.js` | ❌ (asks show as a card) | Plugin, not a hook — OpenCode has no hook protocol |

Sessions are namespaced per agent (`claude-<uuid>`, `codex-<uuid>`, …) so two agents in the
same repo never collide on one card.

## What it does

`agent-desktop-claude-hook.py` reads the hook JSON on stdin and emits bridge events:

| Hook | Bridge event | Island effect |
|------|--------------|---------------|
| `SessionStart` | `session.upsert` (idle) | session appears |
| `UserPromptSubmit` | `session.upsert` (running, title = your prompt) | shows as running |
| `PostToolUse` | `session.message` | activity line: `Read(schema.prisma)`, `Bash(npm test)` |
| `PermissionRequest` | `session.permission` **and blocks** on the socket | Allow/Deny in the island decides the tool call |
| `Notification` (permission/input/idle) | `session.question` | waiting — needs you |
| `Stop` | last message + `session.status` idle (in that order) | "Done — your turn" banner, no badge noise |
| `StopFailure` | `session.status` error | red card |
| `SessionEnd` | `session.ended` | leaves the live list |

Each session carries a `focusApp` (host terminal from `$TERM_PROGRAM`) plus whatever handles
that terminal exposes — `tty`, iTerm session id, kitty window, WezTerm pane, tmux pane,
Terminal.app session. Clicking the card brings that **exact tab or pane** forward.

> First time the island focuses a Terminal/iTerm tab, macOS asks to allow SessionMonitor to
> control that app (Automation permission). Until you allow it, the click still brings the
> terminal app forward — it just can't pick the exact tab.

## Guarantees

- **Never writes to stdout** except a permission decision (stdout on `UserPromptSubmit` /
  `SessionStart` is injected into the agent's context — we must not pollute it).
- **Never fails your session** — every error is swallowed, the hook exits 0, and the wrapper
  forces exit 0 even if the script is missing.
- **Fails open** — no monitor, no answer, killed app: the agent falls back to its own prompt.
- Only Python 3 standard library, invoked via absolute `/usr/bin/python3`. The OpenCode
  plugin uses Node built-ins only.

## Paths

```
~/Library/Application Support/agent-desktop/events.jsonl   # status stream (append-only)
~/Library/Application Support/agent-desktop/monitor.sock   # blocking approve + direct events
```

Override with `AGENT_DESKTOP_EVENTS` / `AGENT_DESKTOP_SOCKET`. Set `AGENT_DESKTOP_DEBUG=1`
to make the OpenCode plugin log its failures to stderr.

## Checks

```bash
../tests/hook-events.sh        # every event → expected bridge events, clean stdout
../tests/permission-e2e.sh     # allow / deny / hook death / monitor down / duplicate app
node ../tests/opencode-plugin.mjs   # drives the plugin without launching opencode
```
