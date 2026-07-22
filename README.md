# Session Monitor

> Ambient menu-bar control surface for AI coding agent sessions (Vibe Island–class).

**Native macOS 14+** · Swift · SwiftUI + AppKit panel  
Not a chat app. Not a centered document window. Not Electron.

## What it is

- **Vibe Island–style HUD** always floating under the notch / top-center (not a tray dropdown)
- Collapsed **black capsule** with live status dots + waiting badge
- Click / **⌘⇧A** → expands into session list; Escape / outside click → collapses (island stays)
- OS notifications on `waiting_input` / `done` / `error`
- Optional tiny menu-bar control for Quit; primary UX is the island
- Sources: **mock sessions** + **Chat Hub JSONL bridge**

## Open & run

```bash
open SessionMonitor/SessionMonitor.xcodeproj
```

In Xcode:

1. Select scheme **SessionMonitor**
2. Destination: **My Mac**
3. Run (⌘R)

Or from terminal:

```bash
cd SessionMonitor
xcodebuild -scheme SessionMonitor -configuration Debug build
# then open the built .app from DerivedData, or:
open ~/Library/Developer/Xcode/DerivedData/SessionMonitor-*/Build/Products/Debug/SessionMonitor.app
```

First launch: allow **notifications** if prompted.

## Usage

| Action | How |
|--------|-----|
| See island | Always under notch / top-center after launch |
| Expand | Click capsule or **⌘⇧A** |
| Collapse | Escape, click outside, or ⌘⇧A again |
| Session actions | Right-click row → copy id / reveal cwd / open Chat Hub (stub) |
| Quit | Right-click menu bar pill → Quit, or footer Quit |

There is **no Dock icon / document window** (`LSUIElement`).

## Bridge path

```
~/Library/Application Support/agent-desktop/events.jsonl
```

Same path as Chat Hub. Override with `AGENT_DESKTOP_EVENTS`.

Details: [docs/bridge.md](./docs/bridge.md)

## Docs

- [Product](./docs/product.md)
- [Architecture](./docs/architecture.md)
- [Bridge](./docs/bridge.md)

## Project layout

```
SessionMonitor/
  SessionMonitor.xcodeproj
  SessionMonitor/
    Models/          SessionStatus, SessionMeta, events
    Services/        store, mock, bridge, notifs, hotkey
    UI/              status item, island panel, list
    AppDelegate.swift
```

## Legacy Electron scaffold

Older Electron files may still exist under `src/` / `package.json` from an earlier experiment. **Canonical product is the native Xcode app** in `SessionMonitor/`.

## Next (real adapters)

- Claude / Grok / Codex / OpenCode producers writing the same JSONL (or dedicated watchers)
- Permission / question action UI
- Jump to Chat Hub session or terminal
- Optional true Dynamic Island private API / HUD polish
