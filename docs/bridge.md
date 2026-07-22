# Chat Hub bridge

Session Monitor is a **consumer** of `SessionEvent` produced by Chat Hub (and local adapters).

## File path (shared)

On macOS:

```
~/Library/Application Support/agent-desktop/events.jsonl
```

Override with env `AGENT_DESKTOP_EVENTS` if needed.

Same path is documented in Chat Hub `docs/bridge.md` and both READMEs.

## Behavior

1. Ensure the JSONL file exists (create empty if missing).
2. On start: **replay** all lines (notifications suppressed) so existing Hub sessions appear.
3. Live-tail via `fs.watch` + short poll for new appends.
4. Forward each valid `session.*` line onto the main `SessionEvent` bus → registry → UI / tray / notifs.

## SessionEvent contract

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

## Standalone

- Without Chat Hub: mock adapter still populates the list; bridge idles on an empty file.
- Without Monitor: Chat Hub still appends events for later consumption.
