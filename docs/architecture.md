# Session Monitor — Architecture

## High level

```
┌─────────────────────────────┐
│ Electron main               │
│  - tray, notifs             │
│  - session registry         │
│  - adapter host             │
└──────────────┬──────────────┘
               │ IPC
┌──────────────▼──────────────┐
│ Renderer (React)            │
│  - session list             │
│  - detail / permission UI   │
└─────────────────────────────┘
               ▲
               │ SessionEvent
┌──────────────┴──────────────┐
│ Adapters                    │
│  grok | claude | codex |    │
│  opencode | chat-hub bridge │
└─────────────────────────────┘
```

## SessionEvent (shared contract with Chat Hub)

```ts
type SessionStatus = "idle" | "running" | "waiting_input" | "error" | "done"

type SessionEvent =
  | { type: "session.upsert"; session: SessionMeta }
  | { type: "session.status"; id: string; status: SessionStatus }
  | { type: "session.permission"; id: string; requestId: string; summary: string }
  | { type: "session.question"; id: string; requestId: string; prompt: string; options?: string[] }
  | { type: "session.message"; id: string; role: "user" | "assistant" | "system"; preview: string }
  | { type: "session.ended"; id: string; reason: "done" | "error" | "killed" }
```

Monitor **consumes** events. Chat Hub (and CLIs) **produce** them.

## How sessions are discovered

MVP options (prefer simple):

1. **Chat Hub bridge** — shared JSONL at  
   `~/Library/Application Support/agent-desktop/events.jsonl`  
   (see [bridge.md](./bridge.md))
2. **Filesystem hooks** — watch known agent log/state dirs
3. **Process scan** — optional, unreliable; secondary

## Storage

Local JSON/SQLite: session meta only (id, title, provider, cwd, last status, updatedAt).

## Security

- No secrets in renderer
- Adapters run in main process
- Explicit allowlist of spawn/watch paths
