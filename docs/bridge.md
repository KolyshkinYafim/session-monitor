# Chat Hub bridge

Session Monitor **consumes** `SessionEvent` JSONL produced by Chat Hub.

## Path

```
~/Library/Application Support/agent-desktop/events.jsonl
```

Override with env `AGENT_DESKTOP_EVENTS`.

Matches Chat Hub `docs/bridge.md`.

## Behavior

1. Ensure file exists (create empty if missing).
2. Replay existing lines on start (`running` / `waiting_input` coerced to `idle` during replay).
3. Live-tail via FS events + short poll.
4. Forward validated events into `SessionStore`.

## Format

Append-only JSONL, one event per line. See Chat Hub bridge doc for examples.
