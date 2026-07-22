# Session Monitor — Architecture

Native **macOS 14+** menu bar app (Swift / SwiftUI + AppKit panel).

## High level

```
┌──────────────────────────────┐
│ AppKit host                  │
│  - NSStatusItem (badge)      │
│  - NSPanel island (top)      │
│  - global hotkey             │
│  - UserNotifications         │
└──────────────┬───────────────┘
               │ @Observable store
┌──────────────▼───────────────┐
│ SessionStore                 │
│  apply(SessionEvent)         │
└──────────────▲───────────────┘
               │
     ┌─────────┴──────────┐
     │                    │
 MockProducer      ChatHubBridge
 (timer cycle)     (JSONL tail)
```

## Session model

```swift
enum SessionStatus { idle, running, waitingInput, error, done }

struct SessionMeta {
  id, title, provider, cwd?, status, updatedAt, createdAt
}
```

JSON bridge uses snake_case status `waiting_input` (maps to `waitingInput`).

## SessionEvent

- `session.upsert`
- `session.status`
- `session.ended`
- `session.permission` / `session.question` (status → waiting)
- `session.message` (touch updatedAt)

Monitor **consumes** events. Chat Hub (and CLIs later) **produce** them.

## Chat Hub bridge path

```
~/Library/Application Support/agent-desktop/events.jsonl
```

Override: `AGENT_DESKTOP_EVENTS`. Same contract as Chat Hub `docs/bridge.md`.

## UI shell

- `LSUIElement` — no Dock icon, no main window on launch
- Status item opens a borderless floating `NSPanel` under the menu bar / notch region
- Hide on Escape, click outside, or resign key
- Hotkey: **⌘⇧A**

## Security

- Local filesystem only
- No secrets in UI
- Sandbox off for MVP (needs Application Support + optional cwd reveal)
