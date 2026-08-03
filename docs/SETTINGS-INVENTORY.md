# Settings inventory — Vibe Island vs Session Monitor

**Purpose:** living checklist of settings UI / behavior so we can clone parity from screenshots without guessing.  
**Updated:** 2026-07-28  
**Sources:** Vibe Island settings screenshots (General, Integrations, Notifications + filters) + our code (`Preferences.swift`, `SettingsView.swift`).

**Legend**

| Mark | Meaning |
|------|---------|
| ✅ | Implemented and wired to real behavior |
| 🟡 | UI exists / partial — flag or placeholder only |
| ❌ | Not in our product yet (documented for clone) |
| 🚫 | Out of scope for now (billing / proprietary) |

Open our settings: **menu bar icon → right-click → Settings…** or **gear ⚙** in the expanded island list.

---

## 1. Sidebar sections

| Section | Vibe Island | Session Monitor | Notes |
|---------|-------------|-----------------|-------|
| General | ✅ | ✅ | Ours thinner; Vibe has more toggles |
| Integrations | ✅ | 🟡 | Ours: status + hook install; Vibe: per-CLI toggles |
| Notifications | ✅ | 🟡 | Ours: waiting/done/error only |
| Display | ✅ | ✅ | Notch offsets + width + screen |
| Sound | ✅ | ✅ | Enable + volume + preview |
| Usage | ✅ | 🟡 | Placeholder page only |
| Shortcuts | ✅ | 🟡 | Read-only list (⌘⇧A, Esc) |
| SSH Remote | ✅ | 🟡 | Labs flag + copy only |
| Labs | ✅ | 🟡 | Experimental flags |
| Pass / billing | ✅ | 🚫 | Not cloning paid pass |
| About | ✅ | ✅ | Version + bridge paths |

---

## 2. General (from Vibe screenshots)

### System

| Setting | Vibe | Us | Key / behavior |
|---------|------|-----|----------------|
| Launch at Login | ✅ | ✅ | `general.launchAtLogin` — registers/unregisters `SMAppService.mainApp`; the toggle is the only autostart mechanism |

### Expansion

| Setting | Vibe | Us | Key / behavior |
|---------|------|-----|----------------|
| Expand notch on hover | ✅ | ✅ | `general.hoverExpand` → `IslandPanelController.handleHover` |
| Hover duration | ✅ slider (e.g. 0.15s) | ❌ | Ours fixed `IslandTheme.idleCompactDelay` (0.12s leave debounce) |
| Smart suppression | ✅ | ❌ | “Don’t auto-expand when agent’s terminal tab is in focus” |

### Visibility

| Setting | Vibe | Us | Key / behavior |
|---------|------|-----|----------------|
| Hide in fullscreen | ✅ | ❌ | |
| Auto-hide when no active sessions | ✅ | ❌ | |

### Dismissal

| Setting | Vibe | Us | Key / behavior |
|---------|------|-----|----------------|
| Auto-collapse on mouse leave | ✅ | ✅ | Leave timer collapses activity → compact (unless waiting / pin) |
| Auto reveal dwell | ✅ (e.g. 5s) | ❌ | How long panel stays open for completion/warning reveals |
| Dismiss auto reveal on outside click | ✅ | 🟡 | Outside click collapses **expanded** only; not full Vibe “auto reveal” model |
| Idle session cleanup | ✅ (e.g. 2 hours) | ❌ | Drop stale sessions without clear close (Codex/OpenCode/Cursor) |

### Interaction

| Setting | Vibe | Us | Key / behavior |
|---------|------|-----|----------------|
| Disable click-to-jump | ✅ | ❌ | When on, click doesn’t switch terminal/IDE |

### Ours-only (not in Vibe screenshots)

| Setting | Us | Key |
|---------|-----|-----|
| Auto-expand when waiting | ✅ | `general.autoExpandWaiting` |
| Default provider for + New | ✅ | `general.defaultNewProvider` (claude/grok/opencode/codex) |

---

## 3. Integrations (from Vibe screenshots)

### CLI Hooks (per-CLI Active toggles)

| Integration | Vibe | Us |
|-------------|------|-----|
| Claude Code | ✅ Active toggle | 🟡 Detect install in settings; hooks via `hooks/install.sh` (not per-toggle UI) |
| Codex | ✅ | ❌ native hooks (Hub only for Codex spawn) |
| OpenCode | ✅ | ❌ native hooks (Hub only) |
| Gemini CLI | ✅ | ❌ |
| Cursor Agent | ✅ | ❌ |
| Qwen | ✅ | ❌ |
| Grok Build | ✅ | ❌ native (Hub grok adapter exists separately) |
| Kimi Code | ✅ | ❌ |
| Add CLI Branch… | ✅ | ❌ |

### Other Integration settings

| Setting | Vibe | Us |
|---------|------|-----|
| Auto-configure new CLIs | ✅ | ❌ |
| IDE Extensions: VS Code | ✅ Install/Uninstall | ❌ |
| IDE Extensions: Cursor | ✅ Install | ❌ |
| Custom Jump Rules | ✅ | ❌ |
| Manage hooks per CLI copy | ✅ | 🟡 Single “Install / repair Claude hooks” button |

### Ours-only

| Item | Status |
|------|--------|
| Chat Hub bridge status | 🟡 Shown as integration row |
| Permission socket path status | 🟡 Shown |
| Reveal bridge folder | ✅ |
| Install Claude hooks script | ✅ |

---

## 4. Notifications (from Vibe screenshots)

### Completion / expand

| Setting | Vibe | Us |
|---------|------|-----|
| Expand panel for completion notifications | ✅ | ❌ (we auto-expand mainly on **waiting**) |
| Subagent & Agent Team notifications mode | ✅ picker | ❌ |
| Follow-up “Remind me again” delay | ✅ Off / delays | ❌ |
| Include: Needs your response | ✅ | 🟡 Covered by notify waiting |
| Include: Completed tasks | ✅ | 🟡 notify done toggle |

### Quiet scenes

| Setting | Vibe | Us |
|---------|------|-----|
| Focus mode | ✅ | ❌ |
| Screen locked or asleep | ✅ | ❌ |
| Screen recording or sharing | ✅ | ❌ |

### Filters

| Setting | Vibe | Us |
|---------|------|-----|
| Built-in: Codex internal workers | ✅ | ❌ |
| Blocked launcher apps (+ Add App) | ✅ | ❌ |
| Custom Filters: Directory (patterns, presets) | ✅ | ❌ |
| Custom Filters: First Prompt (starts with / contains) | ✅ | ❌ |
| Presets (Codex Memory Writer, Claude-Mem, Craft Agent, …) | ✅ | ❌ |
| Right-click card → add filter | ✅ | ❌ |

### Ours-only

| Setting | Key | Wired |
|---------|-----|--------|
| Notify waiting | `notify.waiting` | ✅ OS notification |
| Notify done | `notify.done` | ✅ |
| Notify error | `notify.error` | ✅ |

---

## 5. Display (Vibe screenshots batch #9–11)

### Notch (collapsed strip style)

| Setting | Exact UI | Vibe | Us | Notes |
|---------|----------|------|-----|-------|
| Preview strip | Live preview of notch pill | ✅ | ❌ | Shows sample session in wallpaper mock |
| **Clean** style | “More space for menu bar” — dots + count only | ✅ | 🟡 | Our compact is similar (dots + number) but not a named preset |
| **Detailed** style | “Session titles & status at a glance” — title + status in strip | ✅ | ❌ | Compact does not show title/status text in strip |
| Display picker | **Display** → e.g. Main Display | ✅ | ✅ | `island.screenName` |

### Panel size

| Setting | Exact UI | Vibe | Us | Notes |
|---------|----------|------|-----|-------|
| Content Font Size | e.g. **11pt (Default)** | ✅ | ❌ | Fixed fonts in theme |
| Completion Card Height | slider, e.g. **120pt** | ✅ | ❌ | |
| Max Panel Height | slider, e.g. **560pt** | ✅ | 🟡 | Fixed board heights in `IslandGeometry` |
| Max Panel Width | slider, e.g. **640pt** | ✅ | 🟡 | Width scale Compact/Normal/Wide only |

### Session card (toggles + live preview)

| Setting | Exact UI | Vibe | Us | Notes |
|---------|----------|------|-----|-------|
| Show Project Name | toggle | ✅ | 🟡 | Always shown as `projectLabel` — no toggle yet |
| Show Worktree | toggle | ✅ | ❌ | |
| Show AI Model | toggle | ✅ | 🟡 | Model chip when `model` set; no toggle |
| Show Reasoning Effort | toggle | ✅ | ❌ | |
| Show Tasks | “Show the task checklist in each session card” | ✅ | ❌ | |
| Show Subagents | child agents; else running count | ✅ | ❌ | |
| Show Agent Activity Detail | toggle | ✅ | 🟡 | `display.showActivityDetail` + `lastActivity` on card |

Preview card content (for clone of card layout, not only toggles):

- Status dot · **project** · worktree/path · title · provider chip · host chip  
- “You: …” prompt line  
- “Editing file · 12s” activity  
- **Tasks** checklist (done / in progress / open)  
- **Agents (N)** subagent rows with tool lines  

### Tuning

| Setting | Exact UI | Vibe | Us | Key |
|---------|----------|------|-----|-----|
| Notch width | slider **0pt** = macOS API | ✅ | ✅ | `display.notchWidthOffset` |
| Notch height | slider **0pt** = macOS API | ✅ | ✅ | `display.notchHeightOffset` |
| Help | “Fine-tune notch dimensions…” | ✅ | ✅ | Copy in Settings Display |

### Ours-only Display

| Setting | Us | Key |
|---------|-----|-----|
| Island width Compact/Normal/Wide | ✅ | `island.widthStyle` |
| Show folder paths | ✅ | `display.showPaths` |
| Show status chips RUNNING/WAITING | ✅ | `display.showStatusChips` |

---

## 6. Sound (Vibe screenshots batch #12–13)

### Master

| Setting | Exact UI | Vibe | Us | Key |
|---------|----------|------|-----|-----|
| Enable Sound Effects | toggle | ✅ | ✅ | `soundsEnabled` |
| Volume | slider + % (e.g. 30%) | ✅ | ✅ | `sound.volume` |

### Session (per-event pack picker + preview ▶)

| Event | Exact UI subtitle | Vibe pack picker | Us |
|-------|-------------------|------------------|-----|
| Session Start | New Claude / Codex / Gemini session | ✅ “Vibe Island” ▼ + ▶ | 🟡 Fixed system sound “Pop” on running-from-idle |
| Task Complete | AI finished its turn | ✅ | 🟡 “Glass” on done |
| Task Error | Tool failure or API error | ✅ | 🟡 “Basso” on error |

### Interactions

| Event | Exact UI subtitle | Vibe | Us |
|-------|-------------------|------|-----|
| Approval Needed | Permission or question pending | ✅ pack + ▶ | 🟡 “Tink” on waiting_input |
| Task Acknowledge | You submitted a prompt | ✅ can be Off | ❌ |

### System

| Event | Exact UI subtitle | Vibe | Us |
|-------|-------------------|------|-----|
| Context Limit | Context window almost full | ✅ | ❌ |
| Idle Reminder | AI is waiting for your input | ✅ can be Off | ❌ |
| Spam Detection | 3+ prompts in 10 seconds | ✅ can be Off | ❌ |

### My Sounds / Quiet / Filters

| Setting | Exact UI | Vibe | Us |
|---------|----------|------|-----|
| My Sounds | “No imported sounds yet” + **Add Sound…** | ✅ | ❌ |
| Quiet Hours | Silence during quiet hours + time range | ✅ | ❌ |
| Auto-detect probe sessions | Mutes health-check (CodexBar, ClaudeProbe…) | ✅ | ❌ |

### Ours-only Sound

| Item | Us |
|------|-----|
| Preview waiting sound button | ✅ in Settings → Sound |

---

## 7. Usage (Vibe screenshot batch #14)

| Setting | Exact UI | Vibe | Us |
|---------|----------|------|-----|
| Show Usage Limits | Display subscription usage limits in the notch panel header | ✅ | ❌ placeholder page |
| Display Value | e.g. **Used** (picker) | ✅ | ❌ |
| Preferred Provider | e.g. **Auto (follow session)** | ✅ | ❌ |
| Show Reset Cards | Codex Reset Cards + earliest expiry in usage header | ✅ | ❌ |

---

## 8. Shortcuts (Vibe screenshots batch #15–16)

### Modifier Key

| Setting | Exact UI | Vibe | Us |
|---------|----------|------|-----|
| Modifier Key | e.g. **⌃ Control** | ✅ | ❌ fixed combos |

### Global Shortcuts

| Action | Exact UI description | Vibe binding example | Us |
|--------|---------------------|----------------------|-----|
| Enable Keyboard Shortcuts | master toggle without clearing maps | ✅ | ❌ always on |
| Open Switcher | Quick tap Alfred-style; hold = cycle like ⌘Tab | ✅ e.g. ⌃ + letter | ❌ |
| Reverse Switcher | Shift + switcher while open | ✅ toggle + combo | ❌ |
| Collapse Panel | Active only when expanded | ✅ **esc** | ✅ Esc (not remappable) |
| Toggle expanded (ours) | — | — | 🟡 **⌘⇧A** fixed |

### Panel Shortcuts (active while panel expanded; hold modifier shows hints)

| Action | Vibe example | Us |
|--------|--------------|-----|
| Approve | ⌃ + H | ❌ (click Allow only) |
| Deny | ⌃ + T | ❌ |
| Always Allow | ⌃ + … | ❌ |
| Bypass Permissions | ⌃ + … | ❌ |
| Jump to Terminal | ⌃ + E | 🟡 click row → jump |
| Select Option | ⌃ + 1–9 | ❌ |
| Submit Multi-Select | ⌃ + Enter | ❌ |
| Navigate Sessions | ↑ ↓ | ❌ |

Help copy: *“All shortcuts below are active while the panel is expanded. Hold your modifier key to reveal hints on every button.”*

---

## 9. SSH Remote (Vibe screenshot batch #17)

| Setting / UI | Exact copy | Vibe | Us |
|--------------|------------|------|-----|
| Intro | “Monitor and approve remote AI CLI sessions from your Notch. Add Host → Set Up → Connect. Requires SSH pubkey auth (or ControlMaster for MFA).” | ✅ | ❌ |
| Hosts empty state | “No hosts configured yet” | ✅ | ❌ |
| Add Host | **+ Add Host** | ✅ | ❌ |
| TCP Port | e.g. **17891** · “restart to apply” | ✅ | ❌ |
| Docker container | collapsible section | ✅ | ❌ |
| Manual install (for restricted networks) | collapsible section | ✅ | ❌ |

### Ours-only SSH

| Item | Us |
|------|-----|
| Labs: experimental SSH UI flag | 🟡 `labs.ssh` — no real hosts UI |
| Settings page placeholder copy | 🟡 |

---

## 10. Labs (Vibe screenshot batch #18)

### Beta Updates

| Setting | Exact UI | Vibe | Us |
|---------|----------|------|-----|
| Beta Updates | “Get early access to new features. Beta versions may be less stable.” | ✅ | ❌ (no Sparkle channels yet) |

### Stability

| Setting | Exact UI | Vibe | Us |
|---------|----------|------|-----|
| Restart when memory is high | “Optional safety net. Relaunches only when memory stays high and all sessions are idle.” | ✅ | ❌ |

### Claude Code

| Setting | Exact UI | Vibe | Us |
|---------|----------|------|-----|
| Use Auto Mode instead of Bypass | “Replace Bypass with Auto Mode. Claude Code decides each action’s safety itself.” | ✅ | ❌ |
| Use Native Claude Code Approvals | “Skip Vibe Island approval cards and approval notifications; let Claude Code handle approvals in the terminal.” | ✅ | 🟡 | We can fail-open to Claude UI if socket down; no settings toggle |

### Codex

| Setting | Exact UI | Vibe | Us |
|---------|----------|------|-----|
| When Codex needs your approval | picker e.g. **Follow focus** · “Auto-reviewed requests are always silent” | ✅ | ❌ |

### Other CLIs

| Setting | Exact UI | Vibe | Us |
|---------|----------|------|-----|
| Cursor Sandbox Approval | picker e.g. **Auto-detect** · “Auto reads Cursor’s YOLO config to decide.” | ✅ | ❌ |

### Ours-only Labs

| Setting | Us | Key |
|---------|-----|-----|
| Tool cards from PostToolUse (preview) | 🟡 flag | `labs.toolCards` |
| SSH Remote UI shell | 🟡 flag | `labs.ssh` |

---

## 11. About (Vibe screenshots batch #19–20)

### Branding / version

| Item | Exact UI | Vibe | Us |
|------|----------|------|-----|
| App name + icon | **Vibe Island** | ✅ | Session Monitor |
| Version | e.g. **v1.0.43** | ✅ | ✅ CFBundleShortVersionString |

### Updates (Sparkle-style)

| Setting | Exact UI | Vibe | Us |
|---------|----------|------|-----|
| Check for Updates | button | ✅ | ❌ |
| Release Notes | “Reopen the notes for this version” + version chevron | ✅ | ❌ |
| Check for updates automatically | toggle | ✅ | ❌ |
| Install updates automatically | toggle · “When off, you’ll see an ↑ button on the panel when an update is ready” | ✅ | ❌ |

### Purchase (Vibe-only)

| Item | Exact UI | Vibe | Us |
|------|----------|------|-----|
| Price lock / purchase | “Your price locked at $14.99 · Click to purchase” | ✅ | 🚫 not cloning Pass/billing |

### Links / support

| Item | Exact UI | Vibe | Us |
|------|----------|------|-----|
| Website | vibeisland.app | ✅ | ❌ |
| Creator | Edward Luo | ✅ | ❌ |
| Join Community | link | ✅ | ❌ |
| Report Bug | GitHub | ✅ | ❌ |
| Send Feedback | hi@vibeisland.app | ✅ | ❌ |

### Diagnostics / maintenance

| Item | Exact UI | Vibe | Us |
|------|----------|------|-----|
| Export Diagnostic Report | “Includes system information and diagnostic logs… redacted… Review before sharing.” | ✅ | ❌ |
| Help Improve Vibe Island | telemetry toggle | ✅ | 🚫 skip unless we add opt-in crash only |
| Acknowledgements | Sparkle, Sentry, ConfettiSwiftUI → | ✅ | 🟡 can list deps later |
| Remove All Auto-Configuration | destructive | ✅ | ❌ (we have hooks uninstall.sh only) |
| Quit Vibe Island | destructive quit | ✅ | ✅ Quit in About / menu |

### Ours-only About

| Item | Us |
|------|-----|
| Bundle id | com.agentdesktop.SessionMonitor |
| Events / commands / socket paths | ✅ |
| Reveal data folder | ✅ |
| Quit Session Monitor | ✅ |

---

## 12. Product card fields (island list — not Settings, but parity)

From product UI comparison (our cards vs Vibe session card):

| Field | Vibe | Us (after product-card work) |
|-------|------|------------------------------|
| Project name | ✅ | ✅ `project` / cwd basename |
| Host (Terminal / Ghostty / Hub) | ✅ | ✅ `hostLabel` |
| CLI / provider chip | ✅ | ✅ |
| Model chip | ✅ | ✅ when `model` set |
| Relative time | ✅ | ✅ `relativeAge()` |
| Status Ready/Running/Waiting | ✅ | ✅ `displayStatus` |
| Closed / chat closed | ✅-ish | ✅ `endedAt` / done |
| Last activity line | ✅ | ✅ `lastActivity` |
| Tasks checklist | ✅ | ❌ |
| Subagents list | ✅ | ❌ |

---

## 13. Clone priority (settings only)

When implementing from future screenshots, prefer this order:

### P0 — feels like a real product daily
1. Hover duration slider (wire to leave/enter debounce)  
2. Auto-collapse on mouse leave (already mostly done) + dwell for waiting  
3. Disable click-to-jump  
4. Idle session cleanup  
5. Hide when no active sessions  
6. **Display:** Clean vs Detailed compact strip  
7. **Display:** Max panel width/height sliders (or keep scale + max caps)  
8. **Display:** Session card toggles (project / model / activity) wired to card  

### P1 — Integrations + Sound depth
9. Per-source toggles: Claude hooks / Chat Hub / (later Codex…)  
10. Per-event sound pickers (Start / Complete / Error / Approval) + Off  
11. Claude hooks install status live refresh  

### P2 — Notifications / Usage / Shortcuts
12. Quiet scenes (Focus / screen sharing)  
13. Directory / first-prompt filters  
14. Completion expand vs glow only  
15. Usage header limits (if we ever read rate_limits)  
16. Remappable panel shortcuts (Approve/Deny/Jump)  

### P3 — Rest of Vibe
17. IDE extensions, custom sound import, Quiet Hours  
18. **SSH:** Add Host, port, Docker/manual install  
19. **Labs:** Beta channel, memory restart, Auto Mode / native approvals  
20. **About:** Sparkle updates, diagnostics export, remove auto-config  
21. Pass / purchase — skip unless productizing paid  

---

## 14. How to extend this doc with new screenshots

For each new Vibe screenshot, add a row:

```markdown
| Setting name (exact UI string) | Section | Vibe ✅ | Us ❌/🟡/✅ | Notes / UserDefaults key |
```

Keep **exact English strings** from the UI so we can match copy later.

---

## 15. Code map (ours)

| Concern | File |
|---------|------|
| Pref keys + defaults | `SessionMonitor/Services/Preferences.swift` |
| Settings UI | `SessionMonitor/UI/SettingsView.swift` |
| Window host | `SessionMonitor/UI/SettingsWindowController.swift` |
| Hover / collapse | `SessionMonitor/UI/IslandPanelController.swift` |
| Sounds | `SessionMonitor/Services/IslandSounds.swift` |
| OS notifications | `SessionMonitor/Services/NotificationService.swift` |
| Session product fields | `SessionMonitor/Models/SessionModels.swift` |

---

## 16. Screenshot batch log

| Batch | Date | Content captured |
|-------|------|------------------|
| #1 | 2026-07-28 | Vibe General: System, Expansion (hover, duration, smart suppression), Visibility, Dismissal (partial) |
| #2 | 2026-07-28 | Vibe General cont.: Smart suppression, Visibility, Dismissal (dwell, outside click, idle cleanup), Interaction (disable click-to-jump) |
| #3 | 2026-07-28 | Vibe Integrations: CLI Hooks list (Claude…Kimi), Active toggles, Add CLI Branch |
| #4 | 2026-07-28 | Vibe Integrations cont.: Auto-configure CLIs, IDE Extensions VS Code/Cursor, Custom Jump Rules |
| #5 | 2026-07-28 | Vibe Notifications: Expand for completion, subagent mode, follow-up reminders |
| #6 | 2026-07-28 | Vibe Notifications: Quiet scenes, Codex workers, Blocked launcher apps |
| #7–8 | 2026-07-28 | Vibe Notifications: Custom Filters Directory + First Prompt presets |
| #9 | 2026-07-28 | **Display:** Notch preview, Clean vs Detailed strip, Display picker, Panel size (font, completion height, max H/W) |
| #10 | 2026-07-28 | **Display:** Session card toggles (project, worktree, model, effort, tasks, subagents, activity) + card preview |
| #11 | 2026-07-28 | **Display:** Tuning notch width/height 0pt = API |
| #12 | 2026-07-28 | **Sound:** Enable, Volume 30%; Session Start/Complete/Error; Interactions Approval/Acknowledge; System start |
| #13 | 2026-07-28 | **Sound:** Context Limit, Idle Reminder, Spam Detection; My Sounds; Quiet Hours; Auto-detect probe sessions |
| #14 | 2026-07-28 | **Usage:** Show limits, Display Value Used, Preferred Provider Auto, Show Reset Cards |
| #15 | 2026-07-28 | **Shortcuts:** Modifier Key, Enable, Open/Reverse Switcher, Collapse esc, Panel Approve/Deny/… |
| #16 | 2026-07-28 | **Shortcuts:** Panel Jump/Options/Navigate + help about hold-modifier hints |
| #17 | 2026-07-28 | **SSH Remote:** intro, empty hosts, Add Host, TCP port 17891, Docker, Manual install |
| #18 | 2026-07-28 | **Labs:** Beta Updates, memory restart, Claude Auto Mode / native approvals, Codex focus, Cursor sandbox |
| #19 | 2026-07-28 | **About:** v1.0.43, Check Updates, auto update toggles, purchase lock $14.99, website/creator |
| #20 | 2026-07-28 | **About cont.:** community, report bug, feedback, diagnostic export, telemetry, acknowledgements, remove auto-config, quit |

**Settings capture complete** for all main Vibe settings tabs (except Pass if separate later). Island product UI screenshots can continue in a separate doc if needed.

### Quick parity score (settings surface only, rough)

| Area | Vibe depth | Our depth | Gap |
|------|------------|-----------|-----|
| General | high | medium | hover ms, smart suppression, hide modes, cleanup |
| Integrations | high | low | per-CLI toggles, IDE extensions |
| Notifications | high | low | quiet scenes, filters, reminders |
| Display | high | medium | Clean/Detailed, panel max size, card field toggles |
| Sound | high | low–medium | per-event packs, quiet hours, import |
| Usage | medium | none | whole page |
| Shortcuts | high | low | remapping, switcher, panel keys |
| SSH | high | none | hosts, port, Docker/manual |
| Labs | medium | low | beta channel, approval modes |
| About | high | low | Sparkle, diagnostics, links (no Pass) |
