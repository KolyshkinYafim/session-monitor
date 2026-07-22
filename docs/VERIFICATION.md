# Session Monitor verification (2026-07-22, post island-reliability fixes)

Runtime-verified against a freshly built Debug `.app`, launched with an isolated scratch bridge
(`AGENT_DESKTOP_EVENTS`/`AGENT_DESKTOP_COMMANDS`) on a **two-display** Mac (main = external
2560×1440, secondary = built-in notch 2560×1664). Geometry read via Accessibility; clicks/keys
synthesized via Quartz.

## Results

| Check | Result | Detail |
|-------|--------|--------|
| Build (Debug) | PASS | `BUILD SUCCEEDED`, **0 warnings** (2 Swift-concurrency warnings fixed) |
| Launch / ingest | PASS | accessory app, tails bridge, no crash through upsert/status/question live-tail |
| Island position — pill | PASS | `(1192, 0)` 176×24 — exact top-center of main display, on-screen |
| Island position — expanded | PASS | `(1084, 0)` 392×420 — recentered for width, still on-screen (**SM-1**: no more X≈−949) |
| Multi-display docking | PASS | docks to primary (origin 0,0), never follows mouse to secondary |
| Expand (status-item / ⌘⇧A) | PASS | 176×24 → 392×420 |
| Expand stability | PASS | stays 392×420 after 4 s idle (no bounce-collapse — the activation race is gone) |
| Collapse — click-outside | PASS | click @ (200,800) outside panel → 392×420 → pill (global **mouse** monitor, no Accessibility) |
| Collapse — Esc | PASS | Escape → 392×420 → pill (**was FAIL** in the previous report) |
| Toggle back | PASS | 2nd press → pill |
| Auto-tuck | PASS | after last waiting clears → pill → **tucked 120×22 after 10 s** (was: never fired) |
| Badge = real waiting only | PASS | 3 sessions (Hub `provider:mock` UUID waiting + real claude + local `mock-` waiting) → **badge = 1** (**SM-4**: Hub-mock counted, local demo excluded) |
| First-click responsiveness | PASS | synthesized click on the pill expands it (`acceptsFirstMouse` → acts on first click) |
| Reverse channel focus/reply | PASS (by composition) | `isMock` gate now open for Hub sessions (proven via badge) + unchanged `CommandBridge` (previously PASS). Live end-to-end with a real Claude session tracked as E2E-1. |

## What works in the island UI now

1. Top-center island (tucked / pill / expanded) — always on the main display, on-screen.
2. Click session row → writes `session.focus` (focuses chat if Hub running).
3. Waiting sessions → Allow/Deny + text reply → `session.reply`.
4. OS notifications on waiting/done/error (real sessions only).
5. Esc / click-outside / ⌘⇧A all collapse reliably without Accessibility permission.
6. Auto-tucks into the menu bar 10 s after nothing needs attention.
