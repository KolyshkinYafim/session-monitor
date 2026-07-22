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
- OS notifications on `waiting_input` / `done` / `error`
- Tray title + dock badge = count of `waiting_input`
- Session meta persisted to `userData/sessions.json`

## Project layout

```
src/
  main/           Electron main (tray, bus, registry, adapters)
  preload/        contextBridge API
  renderer/       React UI
  shared/         SessionEvent types + IPC channels
```

## Next

- One real adapter (Grok hooks, OpenCode, or Chat Hub bridge)
- Permission / question action UI
- Jump to terminal or Chat Hub session
