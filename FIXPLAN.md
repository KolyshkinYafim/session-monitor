# Session Monitor — Review & Fix Plan

Review date: 2026-07-22  
Scope: `session-monitor/` only (docs + `src/**`)

## Executive summary

MVP checklist items that are checked **match the code**, except the intentional open item: **one real adapter**. Security baseline for a read-only monitor is mostly fine (contextIsolation, no nodeIntegration, minimal preload, no shell today). The important gaps are **status liveness** (product metric: zero stuck `running`) and **adapter host shape** before Grok/Claude/Codex/OpenCode land.

---

## 1) Match vs `docs/mvp.md`

| Checklist item | Code | Notes |
|----------------|------|--------|
| Electron + React + TS scaffold | Yes | electron-vite, pnpm |
| Tray + open main window | Yes | `src/main/tray.ts`, click/context menu |
| Session list UI (mock) | Yes | renderer list + mock seeds |
| SessionEvent bus in main | Yes | `src/main/session/bus.ts` |
| Mock adapter status transitions | Yes | cycle running → waiting_input → running → done |
| OS notifs waiting/done/error | Yes | `notifications.ts` + registry |
| Badge = waiting_input count | Yes | tray title + dock badge |
| Persist session list | Yes | `userData/sessions.json` |
| One real adapter | **No** | documented open |
| README how to run | Yes | |

Product non-goals respected: not a notch clone; no full transcript UI.

Architecture gaps vs `docs/architecture.md`: no adapter host, no path allowlist, permission/question payloads not stored (status only).

---

## 2) Findings

### P0 — fix now

| ID | Finding | Path(s) |
|----|---------|---------|
| P0-1 | **Startup race: window loads before IPC handler registered.** Renderer `getSessions()` can fire before `ipcMain.handle(...)`, causing empty/error first paint or invoke failures under slow main / fast renderer. | `src/main/index.ts` |
| P0-2 | **Persisted live statuses rehydrate as truth.** `running` / `waiting_input` restored from disk without a live producer → false “running forever” after crash/quit if adapter does not re-emit (violates product “zero stuck running”). | `src/main/session/registry.ts`, `src/main/session/store.ts` |
| P0-3 | **`sandbox: false` with no compensating comment/need.** Current preload only uses `ipcRenderer` + `contextBridge`; sandbox can and should be on. | `src/main/index.ts` |

### P1 — before real adapters

| ID | Finding | Path(s) |
|----|---------|---------|
| P1-1 | No **Adapter** interface / host lifecycle (`start`/`stop`, id, health). Main hardcodes `MockAdapter`. | `src/main/index.ts`, `src/main/adapters/` |
| P1-2 | No **path allowlist** for watch/spawn (architecture Security). | missing; needed under `src/main/` |
| P1-3 | `session.permission` / `session.question` only flip status; **requestId/prompt/options discarded** — cannot build act UI or route answers. | `src/main/session/registry.ts`, `src/shared/types.ts` |
| P1-4 | `session.status` / `session.ended` for **unknown id silently dropped** — adapters must upsert first; contract undocumented and easy to mis-implement. | `src/main/session/registry.ts` |
| P1-5 | No **staleness / heartbeat** while app is up: if adapter dies mid-session without `session.ended`, status stays `running` forever. | registry + adapters |
| P1-6 | Store load is untyped trust: **no schema validation** of status/id fields from JSON. | `src/main/session/store.ts` |
| P1-7 | No navigation lock (`setWindowOpenHandler` / `will-navigate`) — low risk now (no links), high cost if renderer ever renders untrusted previews. | `src/main/index.ts` |
| P1-8 | No real discovery path (Chat Hub bridge / fs hooks / process scan). | docs vs code |

### P2 — polish

| ID | Finding | Path(s) |
|----|---------|---------|
| P2-1 | Duration UI uses `updatedAt - createdAt` (session age), not time-in-status. Misleading for “how long stuck”. | `src/renderer/src/components/SessionRow.tsx` |
| P2-2 | Mock notifies every cycle (~4s) — noisy for local demos. | `src/main/adapters/mock.ts` |
| P2-3 | Terminal sessions (`done`) retained forever; no prune/archive. | registry/store |
| P2-4 | Dead IPC channel `showWindow` unused. | `src/shared/ipc.ts` |
| P2-5 | No unit tests for registry transitions / hydrate rules. | missing |
| P2-6 | Tray icon is raw RGBA buffer — fine for MVP; template asset later for macOS menu bar contrast. | `src/main/tray.ts` |
| P2-7 | `session.ended` reason `killed` maps to `done` (not a distinct state) — OK unless UI needs “killed”. | `registry.ts` |

---

## 3) Session status reliability

**Today (mock only):** mock always re-upserts on start and cycles; hard to observe stuck `running` unless main freezes.

**Structural failure modes:**

1. Rehydrate `running` after restart without producer (P0-2).
2. Adapter crash without `session.ended` while app stays up (P1-5).
3. Status events before upsert ignored (P1-4) — can look like “adapter broken” not stuck running.
4. UI duration is not a liveness signal (P2-1).

Recommended reliability model (later P1):

- `lastEventAt` on every event
- configurable stale threshold (e.g. 2–5 min for `running`)
- demote to `error` or `idle` + optional notif
- adapters own process exit → must emit `session.ended`

---

## 4) Security

| Control | Status |
|---------|--------|
| `contextIsolation: true` | OK |
| `nodeIntegration: false` | OK |
| Preload surface minimal (read-only sessions) | OK |
| Secrets in renderer | None today |
| Shell/spawn/exec | None today |
| CSP on renderer HTML | Present (basic) |
| `sandbox` | Was false → P0-3 |
| Path allowlist | Missing (P1-2) when adapters watch/spawn |
| Untrusted content | No transcript yet; add nav locks before HTML previews |

---

## 5) Architecture clarity

```
OK today:
  adapters → sessionBus → registry → (persist + IPC broadcast + tray + notifs)
  renderer ← snapshot only

Missing for multi-provider:
  AdapterHost { register, startAll, stopAll }
  interface SessionAdapter { readonly id; start(); stop() }
  pending requests map for permission/question
  optional outbound bus for “user answered”
```

Main vs renderer split is correct. Keep adapters in main only.

---

## 6) Missing pieces for real adapters

Per provider (same contract: emit `SessionEvent` only):

| Provider | Likely discovery | Status sources | Watchouts |
|----------|------------------|----------------|-----------|
| **Grok** | CLI session files / hooks / Chat Hub bridge | agent status events, exit code | path allowlist under `~` project dirs |
| **Claude** | Claude Code session JSON / hooks | permission prompts are first-class | map permission → `session.permission` + keep requestId |
| **Codex** | local session store / CLI events | similar to Claude | never put API keys in events |
| **OpenCode** | opencode state dir / server | fs watch | debounce + partial JSON reads |
| **Chat Hub bridge** | localhost socket or NDJSON file | Hub is source of truth | single multiplex adapter preferred |

Shared requirements before any real adapter:

1. P1-1 Adapter interface + host  
2. P1-2 Path allowlist  
3. P1-3 Pending interaction state  
4. P1-4 Document: upsert-before-status (or auto-create skeleton)  
5. P1-5 Staleness timer  
6. Emit `session.ended` on process exit / watch disconnect  
7. No secrets in `SessionMeta` or event previews  

---

## 7) Concrete fix list (ordered)

1. **[P0]** Register `ipcMain` handlers before `createWindow` / adapter start.  
2. **[P0]** On hydrate: validate meta; demote `running` \| `waiting_input` → `idle` (live only after adapter upsert).  
3. **[P0]** Set `sandbox: true`.  
4. **[P1]** Add `SessionAdapter` + `AdapterHost`; wire mock through host.  
5. **[P1]** Store pending permission/question on session meta (or side map).  
6. **[P1]** Document + optionally auto-skeleton upsert on status for unknown ids.  
7. **[P1]** `lastEventAt` + stale demotion for `running`.  
8. **[P1]** Path allowlist module used by all watchers/spawns.  
9. **[P1]** `setWindowOpenHandler(() => ({ action: 'deny' }))`.  
10. **[P1]** One real adapter (prefer Chat Hub bridge or OpenCode fs).  
11. **[P2]** Duration = time since status change (`statusChangedAt`).  
12. **[P2]** Prune old `done` sessions; dampen mock notifications.  
13. **[P2]** Registry unit tests.

---

## 8) Implemented in this pass

- P0-1 IPC bootstrap order  
- P0-2 Hydrate demotion + basic validation  
- P0-3 `sandbox: true`  
- Small related: deny window open / external navigation (cheap hardening next to P0 window setup)
