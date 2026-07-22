# Session Monitor — Product

## Problem

Много agent-сессий (Grok, Claude, Codex, OpenCode) → не видно:

- кто running / stuck
- кому нужен input / permission
- когда done

T3 и похожие chat-shells плохо держат multi-session overview. Notch-apps (Vibe Island) хороши на macOS, но это не chat hub и не всегда multi-provider deep.

## Goals

1. **One glance** — все активные сессии
2. **Reliable status** — только из event bus, не «Working timer навечно»
3. **Notifications** — waiting_input, done, error, permission
4. **Jump** — focus Chat Hub tab / terminal / project path
5. **Local-first** — без cloud

## Primary users

Devs running 3–10 parallel coding agents.

## Core flows

### F1 — See sessions
Tray / main compact list: title, provider, cwd, status, duration.

### F2 — Get notified
OS notification when status → `waiting_input` | `done` | `error`.

### F3 — Act (v1+)
- Allow / Deny permission
- Pick answer option
- Open related Chat Hub session or terminal

### F4 — Quiet hours / filters (later)
Mute done, only waiting_input, per-project filter.

## Non-goals (v0–v1)

- Full transcript UI
- Model marketplace
- Team sync
- Perfect Mac notch clone

## Success metrics

- «Нужен input» видно < 2s без alt-tab в каждый terminal
- Zero stuck `running` when process exited
- Works with ≥2 providers in MVP
