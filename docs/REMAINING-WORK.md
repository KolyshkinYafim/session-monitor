# Session Monitor — remaining work

**Reviewed:** 2026-08-18 against `main` @ `8e6c77b`. Everything already shipped has been
dropped from this file — it lists only what is still open.
**Settings reference:** [SETTINGS-INVENTORY.md](./SETTINGS-INVENTORY.md) (Vibe Island parity table)
**Bridge contract:** [bridge.md](./bridge.md) — authoritative for the wire format, the trim
lock and the permission socket.

## Interaction

- **Island keyboard shortcuts.** No Approve / Deny / Jump keys, no ↑↓ row navigation, no
  ⌃1–9 select. Only Esc is handled (the monitors in `IslandPanelController`), and
  `IslandUIState.selectedSessionId` has no keyboard writer — it is only ever set by a click.
- **Hover open delay.** The *close* delay is a real slider (`hoverLeaveDelay`), but the
  *open* dwell is a hardcoded 0.12 s timer (`IslandPanelController`'s enter timer) with no
  preference behind it.
- **Remappable shortcuts.** The Shortcuts settings page is a read-only list (⌘⇧A, Esc,
  menu-bar click). No recorder.
- **Ghostty / Warp exact-pane jump.** Both fall back to app-level focus (`CommandBridge`).
  Needs OSC 2 title parsing plus Accessibility.

## Session-card depth

- Tasks checklist, subagents list, worktree label and reasoning-effort display all remain
  unbuilt — and cannot be built UI-first: `SessionMeta` carries none of these fields and
  `SessionEventCodec.session(_:)` parses exactly the current set, so each one needs a
  bridge-contract change on both sides first.

## Hooks and integrations

- **Competing blocking `PermissionRequest` hooks.** This project's
  `agent-desktop-claude-hook.py` and Vibe Island's `vibe-island-bridge` can both be
  registered; both fire, both prompt, the first answer wins. `hooks/install.sh` warns, and
  under a real TTY offers to strip Vibe Island's hook (both asserted by
  `tests/hook-events.sh`) — but a non-interactive install still leaves both in place, and
  there is no in-app way to resolve the conflict after the fact.
- **Per-source enable** (Hub / Claude terminal / codex / grok / opencode). The Integrations
  page is status rows plus one "Install / repair Claude hooks" button.
- **"Hooks installed" indicator** (`hookInstalled` in `SettingsView`) greps only
  `~/.claude/settings.json` for the hook command string; the codex / grok / opencode
  configs are not checked.
- **Gemini integration.** claude + codex report by hook, grok by hook (monitor-only, no
  permission event), opencode by plugin — Gemini has nothing.
- **Compiled hook binary.** The hook is `/usr/bin/python3` + stdlib.

## Product surfaces

- **Usage / limits page** — placeholder text, zero controls.
- **Labs flags read by nothing.** `labs.ssh` and `labs.toolCards` are declared, persisted
  and bound in Settings, but no other code reads them (the toolCards hint admits it
  verbatim: *"Flag only — card rendering does not read it in this build"*).
- **Sparkle auto-update + release notes** — not built.
- **Deep link** `agentdesktop://session/{id}` — not built; JSONL + socket only.
- **Shared TS+Swift contract package.** Still three hand-written codecs (Swift
  `SessionEventCodec`, Chat Hub's `bridge.ts`, the Python hook) that must be changed
  together.
- **Directory / first-prompt notification filters** and **blocked launcher apps** — not built.
- **Import custom sounds.** The picker enumerates `/System/Library/Sounds` and
  `~/Library/Sounds`, so a file dropped there shows up, but there is no in-app import.

## Verification still owed

- A human clicking **Allow** on a live Claude permission turn. The transport is proven both
  ways by `tests/permission-e2e.sh` (allow / deny / hook EOF / monitor down / duplicate
  instance); the live click has never been observed.

## Chat Hub items that the island feels

- Hub's `session.upsert` carries `project` and `model` but no `source` field, so the island
  cannot label a card "hub" vs "terminal" from the payload — it infers from `focusApp`.
- The Hub has no in-app Allow/Deny (its banner says *"Answer in the notch island"*), so the
  island is the only approval surface for Hub sessions too.
