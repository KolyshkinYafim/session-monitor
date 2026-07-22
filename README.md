# Session Monitor

> Ambient control surface for AI coding agent sessions (Vibe Island–class).

A **native macOS** menu-bar "island" HUD (Swift / AppKit + SwiftUI). It tails the Chat Hub
event bridge and surfaces live agent sessions — statuses, a waiting-input badge, and quick
reply — as a floating pill at the top-center of the display.

> A previous Electron prototype (`src/`) was removed once the native app superseded it — the
> Swift app under `SessionMonitor/` is the only implementation.

Primary UX is **not** a centered document window and **not** only a tray dropdown.

## Vibe Island

- Floating **black capsule** at **top-center** of the Mac display (menu bar / notch zone)
- Live status dots + waiting badge (real agents only)
- Click → expand session list; Esc / click-outside / ⌘⇧A → collapse; auto-tucks when idle
- OS notifications: `waiting_input` / `done` / `error`
- Source: **Chat Hub JSONL bridge** (plus an optional local mock producer for UI tests)

```
                    ┌─────────────────┐
                    │ ● ●  1  Waiting │  ← island pill (always on top)
                    └─────────────────┘
         ─────────── menu bar / notch ───────────
```

## Run

```bash
open SessionMonitor/SessionMonitor.xcodeproj
```

Xcode → scheme **SessionMonitor** → **My Mac** → Run (⌘R). Hotkey: **⌘⇧A** to expand/collapse.

Or build/run from the CLI:

```bash
xcodebuild -project SessionMonitor/SessionMonitor.xcodeproj -scheme SessionMonitor -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/SessionMonitor-*/Build/Products/Debug/SessionMonitor.app
```

There is **no Dock document window** (`LSUIElement`-style ambient app). Enable the local demo
producer for UI testing with `SESSION_MONITOR_MOCK=1` (off by default).

## Bridge path

```
~/Library/Application Support/agent-desktop/events.jsonl   (Hub → Monitor)
~/Library/Application Support/agent-desktop/commands.jsonl  (Monitor → Hub)
```

Override: `AGENT_DESKTOP_EVENTS` / `AGENT_DESKTOP_COMMANDS`. See [docs/bridge.md](./docs/bridge.md).

## Docs

- [Product](./docs/product.md)
- [Architecture](./docs/architecture.md)
- [Bridge](./docs/bridge.md)
- [MVP](./docs/mvp.md)
- [Verification](./docs/VERIFICATION.md)

## Layout

```
SessionMonitor/          Swift native island (Xcode project — the app)
docs/
```
