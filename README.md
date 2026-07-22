# Session Monitor

> Ambient control surface for AI coding agent sessions.

Electron (macOS first) · TypeScript · React

## What it is

Не «ещё один чат». Это **monitor**:

- список живых agent-сессий
- статусы: `idle` | `running` | `waiting_input` | `error`
- OS notifications + tray badge
- (позже) approve permission / answer question / jump to terminal or Chat Hub window

Аналог по духу: **Vibe Island**, Open Island, Claude Peek — но:

- не notch-only (tray + compact window + optional HUD)
- multi-provider через adapters
- можно работать рядом с Chat Hub или с чистым CLI

## What it is not

- Не full multi-chat IDE
- Не замена Claude Code / Grok Build / OpenCode
- Не cloud relay (всё local)

## Docs

- [Product](./docs/product.md)
- [Architecture](./docs/architecture.md)
- [MVP checklist](./docs/mvp.md)

## Stack (planned)

- Electron
- React + TypeScript
- Zustand or lightweight store
- node adapters reading agent events / logs / hooks

## Status

Docs + empty git repo. App scaffold next.
