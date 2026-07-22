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
| See island | Top-center under menu bar (tucks into “curtain” when idle) |
| Expand | Click pill or **⌘⇧A** |
| Collapse / hide | Esc → pill · ↑ button / idle → tuck into menu bar |
| Open chat | Click a session row (focuses Chat Hub via `commands.jsonl`) |
| Answer agent | On `waiting`: Allow/Deny chips + text field → Send |
| Quit | Right-click menu bar control → Quit |

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
