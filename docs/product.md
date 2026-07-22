# Session Monitor — Product

## Problem

Many parallel AI coding agents (Grok, Claude, Codex, OpenCode, Chat Hub tabs) → hard to see:

- who is running vs stuck
- who needs input / permission
- when work is done

Chat shells keep you inside one conversation. Notch-style ambient UIs are better for multi-session glanceability.

## Goals

1. **One glance** — active sessions in a compact island panel
2. **Reliable status** — driven by events, not fake “working” timers
3. **Notifications** — `waiting_input`, `done`, `error`
4. **Menu bar native** — no big document window on launch
5. **Local-first** — no cloud

## Primary users

Developers running several coding agents at once.

## Core flows

### F1 — See sessions
Menu bar icon opens a top panel: title, provider, cwd, status, relative time.

### F2 — Get notified
OS notification when status becomes `waiting_input` | `done` | `error`.

### F3 — Act (later)
Allow/deny, answer questions, jump to Chat Hub or terminal.

## Non-goals

- Full transcript UI (Chat Hub)
- Electron
- Cloud sync
- Perfect private Notch API clone on day one

## Success metrics

- Needs-input visible in under ~2s without alt-tabbing every terminal
- No permanent `running` after process exit (event or stale policy)
- Works with mock + Chat Hub bridge in MVP
