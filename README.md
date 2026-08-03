# Session Monitor

> Ambient control surface for AI coding agent sessions (Vibe Island–class).

A **native macOS** menu-bar "island" HUD (Swift / AppKit + SwiftUI). It tails the Chat Hub
event bridge and surfaces live agent sessions — statuses, a waiting-input badge, and quick
reply — as a floating pill at the top-center of the display.

> A previous Electron prototype (`src/`) was removed once the native app superseded it — the
> Swift app under `SessionMonitor/` is the only implementation.

Primary UX is **not** a centered document window and **not** only a tray dropdown.

## Vibe Island (notch-native)

Sits **in** the menu-bar / notch band (like Vibe Island), not as a ghost pill under the curtain:

- **Compact / activity strip** — height = menu bar; **left wing** = live session icons, **center** = hardware notch (empty), **right wing** = waiting badge / live count
- **Expanded** — board drops **down** from the strip; list content is below the notch (never clipped under it)
- Modes: `compact` → `activity` → `expanded` (no invisible 4px tuck)
- Click strip / ⌘⇧A → expand; Esc / click-outside → collapse; idle 10s → compact (still visible)
- OS notifications: `waiting_input` / `done` / `error`
- Source: **Chat Hub JSONL bridge** (+ optional `SESSION_MONITOR_MOCK=1`)

```
  [icons] ████ NOTCH ████ [badge]     ← strip in menu bar band
           ┌──────────────────┐
           │ Sessions board   │       ← expands downward only
           └──────────────────┘
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
