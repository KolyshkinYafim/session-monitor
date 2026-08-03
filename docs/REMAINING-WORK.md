# Session Monitor — what is left

**Reviewed:** 2026-08-02 against the Swift tree (uncommitted on `main`).
**Settings reference:** [SETTINGS-INVENTORY.md](./SETTINGS-INVENTORY.md) (Vibe Island parity table)
**Bridge contract:** [bridge.md](./bridge.md) — authoritative for the wire format, the trim
lock and the permission socket.

Legend: ✅ built and wired · 🟢 built, code-level only (never exercised on this machine) ·
🟡 partial, with the missing half named · ❌ not built

The previous revision of this file listed several things as ❌ that are in fact wired
(hover-delay slider, click-to-jump toggle, hide-when-empty, panel width/height, content font
size, the card toggles, Clean/Detailed compact, follow-up reminders, quiet scenes, sound
pickers, diagnostic export). Those rows are corrected below rather than deleted, so the
mistake is visible.

---

## Verified today

| Claim | How it was checked |
|-------|--------------------|
| Release build succeeds with zero warnings | `packaging/install-app.sh` (Xcode 26.1 / Swift 6.2). A plain `xcodebuild build` **fails** — see Gotchas |
| Installed app is real and signed | `/Applications/SessionMonitor.app`, `codesign --verify --deep --strict` passes |
| Which tree the installed app came from | `Contents/Resources/BuildIdentity.plist` → `SMBuildRevision = 6b9208b-dirty`, `SMBuildDate = 2026-08-02T11:46:16Z` |
| `hooks/` ships inside the bundle | `/Applications/SessionMonitor.app/Contents/Resources/hooks/` contains `install.sh`, `agent-desktop-claude-hook.py`, `uninstall.sh`, `opencode/`. The Settings button prefers this copy, and the `~/Desktop/agent-desktop-suite/…` path is only a dev fallback |
| Hook contract | `tests/hook-events.sh` — 13 hook invocations (each asserted exit 0, silent stdout, silent stderr) plus 12 named assertions. **All pass.** |
| Launch is silent | The island used to fire ~609 notification banners and sounds replaying the event log on every start. Fixed — see below |

### Why launch is silent now

`SessionStore.isReplaying`, raised by `ChatHubBridge.withReplay(_:)` around both the startup
drain and the post-rotation re-read from byte 0. The single choke point is
`SessionStore.emitStatusChange`:

```swift
guard !isReplaying else { return }
onStatusChange?(session, status, previous)
```

That one handler drives banners, sounds *and* `panel.pulseForWaiting()`, so the guard kills
all three. Two supports make it honest: `normalizeReplay(_:)` downgrades replayed
`running` / `waitingInput` / `permission` / `question` to `.idle`, and `setActivity` skips the
`idle → running` promotion while replaying.

---

## Corrected P0 — the previous "daily can't-live-without" list

| # | Item | Old status | Actual | Where |
|---|------|-----------|--------|-------|
| P0.1 | Stable hover, configurable leave delay | 🟡 | 🟡 — **close** delay is a real slider (`hoverLeaveDelay`, 0.2–1.5 s, shown in ms, clamped at use). The **open** dwell is a hardcoded `0.12` s `Timer`, no pref, no slider | `IslandPanelController.swift:282, 294` |
| P0.2 | Compact strip readable under the notch | 🟡 | ✅ — `notchWidthOffset` (−40…40) and `notchHeightOffset` (−12…20) sliders both feed `IslandGeometry`, and a live preview of the strip renders in Settings → Display | `SettingsView.swift:306–411` |
| P0.3 | Click-to-jump reliable | 🟡 | 🟢 — jump handles tmux, iTerm2 (session id), Terminal.app (tty), kitty, WezTerm, VS Code / Cursor / Zed. Only tmux/iTerm/Terminal have ever been exercised here, the rest are code-level. Ghostty and Warp still fall back to app-level focus | `CommandBridge.swift` |
| P0.4 | No mock noise by default | 🟡 | ✅ — mock only under `SESSION_MONITOR_MOCK=1`, and `isMock` is `id.hasPrefix("mock-")` so Hub sessions are never mistaken for demos | `MockProducer.swift` |
| P0.5 | Permission Allow/Deny end to end | 🟡 | 🟡 — transport proven both ways (allow / deny / hook EOF / monitor down / duplicate instance, by `tests/permission-e2e.sh`). **A human clicking Allow on a live Claude turn is still unconfirmed.** |
| P0.6 | Display: Clean vs Detailed compact | ❌ | ✅ — `CompactStyle` enum, segmented picker, drives both `compactWidth` and the strip content | `IslandGeometry.swift:6–24` |
| P0.7 | Session-card toggles | 🟡 | 🟡 — three toggles exist and are read: *Show folder paths*, *Show chips (agent · terminal · model)*, *Show last activity line*. There are **no** separate project / model / host / age toggles. Project label, age and status word render unconditionally | `VibeIslandView.swift:205–207, 416–418` |
| P0.8 | Hover duration slider | ❌ | ✅ (close side) — see P0.1 |
| P0.9 | Disable click-to-jump | ❌ | ✅ — `clickToJump`. Off shows the toast *"Click-to-jump is off — enable it in Settings › General"* | `VibeIslandView.swift:525` |
| P0.10 | Auto-hide when no sessions / hide in fullscreen | ❌ | ✅ both — `hideWhenEmpty` and `hideInFullscreen`, re-evaluated on the 400 ms visibility tick. Fullscreen is detected geometrically, deliberately avoiding a screen-recording consent prompt | `IslandPanelController.swift:466–481` |
| P0.11 | Idle session cleanup | ✅ | ✅ — `idleCleanupHours`, default 6, choices `0/1/2/6/12/24`, `0` = never | `AppController.swift:146` |
| P0.12 | Installed app always matches the tree | 🟡 | ✅ — `packaging/stamp-build-identity.sh` writes `BuildIdentity.plist`, with `-dirty` when the tree has uncommitted changes. It stamps a *Resources* plist, not `Info.plist`, because Xcode's `ProcessInfoPlistFile` runs after every script phase and would overwrite it |

---

## Open — Session Monitor

### Interaction

| # | Item | Status | Note |
|---|------|--------|------|
| I.1 | **Island keyboard shortcuts** | ❌ | No Approve / Deny / Jump keys, no ↑↓ row navigation, no ⌃1–9 select. The whole tree contains exactly two `keyCode` references, both `== 53` (Esc), zero `.keyboardShortcut(…)` calls and zero `modifierFlags` reads. `ui.selectedSessionId` has no keyboard writer — it is only ever set by a click |
| I.2 | **Accessibility prompt** | ❌ | `AXIsProcessTrustedWithOptions` appears **nowhere**. The global Esc monitor (`NSEvent.addGlobalMonitorForEvents`) silently receives nothing until the user grants Accessibility by hand, so the advertised global Esc does not fire on a fresh install. The only AX call is the non-prompting `AXIsProcessTrusted()` at `SettingsView.swift:629`, used to reword a footnote |
| I.3 | Hover **open** delay setting | ❌ | Half of the pair — see P0.1 |
| I.4 | Remappable shortcuts | ❌ | The Shortcuts page is a read-only list of three rows (⌘⇧A, Esc, menu-bar click). No recorder |
| I.5 | Ghostty / Warp exact-pane jump | ❌ | Needs OSC 2 title parsing + Accessibility |

### Session-card depth

| # | Item | Status | Note |
|---|------|--------|------|
| C.1 | Tasks checklist on the card | ❌ | |
| C.2 | Subagents list / count | ❌ | |
| C.3 | Worktree label | ❌ | |
| C.4 | Reasoning-effort display | ❌ | |
| C.5 | The model cannot carry any of them | ❌ | `SessionMeta` (`Models/SessionModels.swift:24–47`) is `id, title, provider, project, cwd, model, status, updatedAt, createdAt, endedAt, lastActivity, pending, focusApp, tty, termSession, termIds, source` — and `SessionEventCodec.session(_:)` parses exactly that set, so the bridge cannot deliver these fields either. **All four need a bridge-contract change first, on both sides.** |
| C.6 | Activity line | ✅ | `Read(schema.prisma)`, `Bash(npm test)`, `Edit(queries.ts) +8 −3` — asserted by `tests/hook-events.sh` |

### Hooks and integrations

| # | Item | Status | Note |
|---|------|--------|------|
| H.1 | **Two competing blocking `PermissionRequest` hooks** | 🟡 | Confirmed live in `~/.claude/settings.json` right now: `$HOME/.vibe-island/bin/vibe-island-bridge` and this project's `agent-desktop-claude-hook.py`, both with `timeout: 86400`. Both fire, both prompt, first answer wins, the other is left hanging until Claude moves on. `install.sh` **warns** and does nothing more (asserted by `tests/hook-events.sh` → *"warns about the competing blocking hook"*). Deciding which one owns approvals is a user decision the installer deliberately refuses to make |
| H.2 | Per-source enable (Hub / Claude terminal / codex / grok / opencode) | ❌ | Integrations page is status + one "Install / repair Claude hooks" button |
| H.3 | Live "hooks Active" indicator | 🟡 | Greps `~/.claude/settings.json` for the hook command string, and does not check the codex/grok/opencode configs |
| H.4 | Gemini integration | ❌ | claude + codex by hook, grok by hook (monitor-only, no permission event), opencode by plugin |
| H.5 | Replace the Python hook with a compiled binary | ❌ | Currently `/usr/bin/python3` + stdlib only |

### Product surfaces

| # | Item | Status | Note |
|---|------|--------|------|
| S.1 | Usage / limits page | ❌ | Settings → Usage is placeholder text with zero controls |
| S.2 | SSH remote hosts | ❌ | `labs.ssh` flag is declared, persisted, bound in **two** places, and read by nothing |
| S.3 | `labs.toolCards` flag | ❌ | Same — the Settings hint admits it verbatim: *"Flag only — card rendering does not read it in this build"* |
| S.4 | Sparkle auto-update + release notes | ❌ | |
| S.5 | Deep link `agentdesktop://session/{id}` | ❌ | JSONL + socket only |
| S.6 | Shared TS+Swift contract package | ❌ | Three hand-written codecs (Swift `SessionEventCodec`, TS `bridge.ts`, Python hook) that must be changed together |
| S.7 | Directory / first-prompt notification filters | ❌ | |
| S.8 | Blocked launcher apps | ❌ | |
| S.9 | Import custom sounds | 🟡 | The picker enumerates `/System/Library/Sounds` **and** `~/Library/Sounds`, so a file dropped there shows up. There is no in-app import |

### Corrected — these were listed as missing and are built

| Previously | Now | Where |
|-----------|-----|-------|
| P1.11 Panel width / height sliders | ✅ `panelWidth` 420–820, `maxPanelHeight` 260–760, both feed `IslandGeometry.size` | `IslandPanelController.swift:400–401` |
| P1.12 Content font size | ✅ 11–16 pt, feeds card text **and** row height, so the visible-row count follows it | `IslandGeometry.rowHeight` |
| P2.1 Expand on completion | ✅ `expandForCompletion` (default off) | `IslandPanelController.swift:211` |
| P2.2 Follow-up reminders | ✅ `notify.followUpMinutes`, options `0/1/2/5/10/15/30`. The reminder sound fires even when the banner is muted, on purpose | `NotificationService.swift` |
| P2.3 Quiet scenes | ✅ Focus (reads `~/Library/DoNotDisturb/DB/Assertions.json`), screen locked/asleep, screen recording or sharing. Each defaults to "not quiet" when it cannot read the state, so it never mutes silently | `QuietScenes` |
| P2.6 Per-event sound pickers + Off | ✅ Six events (`sessionStart`, `taskComplete`, `taskError`, `approvalNeeded`, `taskAcknowledge`, `idleReminder`), each with a picker and a ▶ preview that bypasses master-off and quiet hours | `IslandSounds.swift` |
| P2.7 Quiet Hours | ✅ From/To as minute-of-day, handles the midnight wrap | `IslandSounds.isQuietHour` |
| P2.10 Auto-reveal dwell | ✅ `autoRevealDwell` 0–20 s, `0` = stay open. Distinct from the pointer's `hoverLeaveDelay` | `IslandPanelController.swift:241–263` |
| P3.5 Export diagnostic report | ✅ About page → `NSSavePanel`, whitelist redaction, tails the last 256 KB / 60 lines | `SettingsView.swift:661–696` |
| P3.9 JSONL trim under a lock | ✅ but **not `flock`** — the lock is an `O_CREAT\|O_EXCL` sibling file `events.jsonl.lock`, because Node exposes no `flock`. `flock` is still used for `monitor.lock` (single instance), which is a different thing | `ChatHubBridge.acquireBridgeLock`, `AppController.SingleInstance` |

---

## Gotchas

**Building.** A plain `xcodebuild -project … build` fails with *"resource fork, Finder
information, or similar detritus not allowed"*. The repo lives under an iCloud-synced
Desktop, and every file the syncer touches picks up a `com.apple.FinderInfo` xattr that
`codesign` refuses. Use `packaging/install-app.sh`, which builds into
`${TMPDIR}/SessionMonitor-release` (outside the synced tree), `xattr -cr`s the copy in
`/Applications`, then ad-hoc signs it. Do not reorder those steps — strip before signing,
never after.

**Two islands.** A Debug build launched over the installed one would unlink the live
`monitor.sock`. `SingleInstance.acquire()` (`flock` on `monitor.lock`) makes the second copy
exit instead. If hooks stop getting answers, check that only one SessionMonitor is running.

**Launch at login** is the app's own `SMAppService` login item, driven by Settings → General.
`install-app.sh` deletes any legacy `~/Library/LaunchAgents/com.agentdesktop.SessionMonitor.plist`
it finds, because a LaunchAgent would start the island regardless of what the toggle says.

---

## Chat Hub items that touch the island

| # | Item | Status |
|---|------|--------|
| CH.1 | Hub `session.upsert` always carries `model`, `project`, `source` | 🟡 — `project` and `model` yes, **`source` no**: Chat Hub's `SessionMeta` has no such field, so the island cannot label a card "hub" vs "terminal" from the payload. It infers from `focusApp` |
| CH.2 | Hub packaged app fails `codesign --verify` | ❌ — `electron-builder.yml` has `identity: null` — see `chat-hub/docs/roadmap-v2.md` |
| CH.3 | In-app Allow/Deny in the Hub | ❌ — the Hub banner says *"Answer in the notch island"*, so the island is currently the only approval surface for a Hub session too |
| CH.4 | Bridge rotation and watchdog | ✅ — both built and tested on the Hub side |

---

## Definition of done for "a good daily island"

- [x] Compact strip never clipped by the notch (offsets + preview)
- [x] Hover opens and closes without thrash (close delay configurable)
- [x] Card shows project · host · CLI · model · status · age · activity
- [x] Click focuses the exact terminal tab (tmux / iTerm / Terminal verified)
- [x] Settings actually drive the UI (width, height, font, strip style, screen)
- [x] Mock off by default, no fake projects
- [x] One install path — `packaging/install-app.sh` → `/Applications`, identity stamped
- [x] Launch is silent — no banner storm replaying the log
- [ ] A human clicks Allow on a live Claude permission and the tool call proceeds
- [ ] Keyboard: Approve / Deny / Jump / ↑↓ / ⌃1–9
- [ ] Global Esc works on a fresh install (needs the Accessibility prompt)
- [ ] Exactly one blocking `PermissionRequest` hook registered

---

## Related files

| Doc | Role |
|-----|------|
| [bridge.md](./bridge.md) | **Authoritative** — wire format, trim lock, permission socket, dev switches |
| [SETTINGS-INVENTORY.md](./SETTINGS-INVENTORY.md) | Vibe Island vs us, setting by setting |
| [../hooks/README.md](../hooks/README.md) | What each hook emits, what gets installed where |
| [../tests/README.md](../tests/README.md) | How to run the two check scripts |
| [product.md](./product.md), [VERIFICATION.md](./VERIFICATION.md), [architecture.md](./architecture.md) | Older, not re-verified in this pass |
| Suite [TODO.md](../../TODO.md) | Both apps, one list |
