# Session Monitor

> Ambient control surface for AI coding agent sessions.

Electron (macOS first) · TypeScript · React · pnpm

## What it is

Not another chat shell. This is a **monitor**:

- list of live agent sessions
- statuses: `idle` | `running` | `waiting_input` | `error` | `done`
- OS notifications + tray badge (waiting_input count)
- multi-provider via adapters (mock today; real adapters next)

Spiritually close to Vibe Island / Claude Peek — but tray + compact window first, not a notch-only clone.

## Docs

- [Product](./docs/product.md)
- [Architecture](./docs/architecture.md)
- [MVP checklist](./docs/mvp.md)

## Requirements

- macOS (primary), Node ≥ 20, pnpm

## How to run

```bash
pnpm install
pnpm dev
```

Build production bundles (main / preload / renderer → `out/`):

```bash
pnpm build
pnpm typecheck
```

## What works (MVP)

- Electron main + React renderer (electron-vite)
- Tray icon; click opens main window
- Session list UI (title, provider, cwd, status, duration)
- `SessionEvent` bus in main process
- Mock adapter cycling: `running` → `waiting_input` → `running` → `done` (then restarts)
- **Chat Hub bridge**: tails shared JSONL and shows Hub sessions
- OS notifications on `waiting_input` / `done` / `error`
- Tray title + dock badge = count of `waiting_input`
- Session meta persisted to `userData/sessions.json`

## Chat Hub bridge

Shared append-only event log (same path as Chat Hub):

```
~/Library/Application Support/agent-desktop/events.jsonl
```

| Side | Role |
|------|------|
| Chat Hub | Produces `SessionEvent` lines |
| Session Monitor | Replays + tails; merges into session list |

Details: [docs/bridge.md](./docs/bridge.md). Override with `AGENT_DESKTOP_EVENTS`.

Both apps stay usable alone (mock sessions without Hub; Hub still writes without Monitor).

## Project layout

```
src/
  main/           Electron main (tray, bus, registry, adapters)
  preload/        contextBridge API
  renderer/       React UI
  shared/         SessionEvent types + IPC channels + bridge path
```

## Next

- Real CLI adapters (Grok / OpenCode) alongside the Hub bridge
- Permission / question action UI
- Jump to terminal or Chat Hub session
