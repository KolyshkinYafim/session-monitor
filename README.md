# Session Monitor

> Ambient control surface for AI coding agent sessions (Vibe Island–class).

Two implementations live in this repo:

| Surface | Stack | Role |
|---------|--------|------|
| **Native island** (recommended) | Swift / SwiftUI · `SessionMonitor/` | Real top-center HUD under menu bar / notch |
| **Electron MVP** | `src/` · `pnpm dev` | Same product loop for cross-platform iteration |

Primary UX is **not** a centered document window and **not** only a tray dropdown.

## Vibe Island (what you want)

- Floating **black capsule** at **top-center** of the Mac display (menu bar / notch zone)
- Live status dots + waiting badge
- Click → expand session list; blur / collapse control → pill again
- OS notifications: `waiting_input` / `done` / `error`
- Sources: mock sessions + **Chat Hub JSONL bridge**

```
                    ┌─────────────────┐
                    │ ● ●  1  Waiting │  ← island pill (always on top)
                    └─────────────────┘
         ─────────── menu bar / notch ───────────
```

## Run — native (recommended on macOS)

```bash
open SessionMonitor/SessionMonitor.xcodeproj
```

Xcode → scheme **SessionMonitor** → **My Mac** → Run (⌘R).

There is **no Dock document window** (`LSUIElement` style ambient app).

## Run — Electron island MVP

```bash
pnpm install
pnpm dev
```

Electron now uses the same **top-center always-on-top pill** (not a 420×560 document window).  
Dock icon is hidden; tray remains as a secondary expand control.

## Bridge path

```
~/Library/Application Support/agent-desktop/events.jsonl
```

Override: `AGENT_DESKTOP_EVENTS`. See [docs/bridge.md](./docs/bridge.md).

## Docs

- [Product](./docs/product.md)
- [Architecture](./docs/architecture.md)
- [Bridge](./docs/bridge.md)
- [MVP](./docs/mvp.md)

## Layout

```
SessionMonitor/          Swift native island (Vibe Island class)
src/                     Electron main/preload/renderer island MVP
docs/
```
