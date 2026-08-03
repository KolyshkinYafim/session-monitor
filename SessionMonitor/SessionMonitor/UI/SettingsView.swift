import AppKit
// ApplicationServices' AX* globals (e.g. kAXTrustedCheckOptionPrompt) aren't annotated
// Sendable, so a plain import trips "not concurrency-safe" under this project's
// SWIFT_STRICT_CONCURRENCY=complete. @preconcurrency defers those checks to Apple.
@preconcurrency import ApplicationServices
import Darwin
import SwiftUI
import UniformTypeIdentifiers

/// Vibe-style settings: sidebar sections + detail pane.
/// Isolated as a whole because the settings models it owns are main-actor state.
@MainActor
struct SettingsView: View {
    @Bindable var prefs: Preferences
    var onApplyDisplay: () -> Void
    var onQuit: () -> Void

    @State private var section: Preferences.SettingsSection = .general
    /// Also what re-reads the integration status rows after the installer runs.
    @State private var hookInstallResult: String?
    @State private var diagnosticResult: String?
    @State private var sounds = SoundSettingsModel()
    @State private var notifications = NotificationSettingsModel()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                detail
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Session Monitor")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ForEach(Preferences.SettingsSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .foregroundStyle(section == item ? Color.white : Color.accentColor)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(section == item ? Color.accentColor : Color.accentColor.opacity(0.12))
                            )
                        Text(item.title)
                            .font(.system(size: 13, weight: section == item ? .semibold : .regular))
                            .foregroundStyle(section == item ? Color.primary : Color.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(section == item ? Color.primary.opacity(0.06) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .general: generalPage
        case .integrations: integrationsPage
        case .notifications: notificationsPage
        case .display: displayPage
        case .sound: soundPage
        case .usage: usagePage
        case .shortcuts: shortcutsPage
        case .ssh: sshPage
        case .labs: labsPage
        case .about: aboutPage
        }
    }

    private func pageTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 16)
    }

    // MARK: General

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("General", subtitle: "Startup, hover behavior, defaults for new chats.")

            groupBox("Startup") {
                toggle("Launch at login", isOn: $prefs.launchAtLogin, hint: "Registers a macOS login item. Unsigned dev builds cannot register one — run from /Applications.")
            }

            groupBox("Island behavior") {
                toggle("Expand on hover", isOn: $prefs.hoverExpand, hint: "Peek the session list when the pointer enters the island.")
                Divider()
                toggle("Auto-expand when waiting", isOn: $prefs.autoExpandOnWaiting, hint: "Open the list as soon as an agent needs input or permission.")
                Divider()
                toggle(
                    "Smart suppression",
                    isOn: $prefs.smartSuppression,
                    hint: "Don't auto-expand when the agent's terminal tab is already in focus. The sound and the badge still fire."
                )
                .disabled(!prefs.autoExpandOnWaiting)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Auto reveal dwell")
                        Spacer()
                        Text(prefs.autoRevealDwell == 0 ? "Stays open" : "\(Int(prefs.autoRevealDwell)) s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $prefs.autoRevealDwell, in: 0...20, step: 1)
                    Text("How long a list opened by an event stays up before returning to the strip. 0 keeps it open until you or the agent close it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Stay open after pointer leaves")
                        Spacer()
                        Text("\(Int(prefs.hoverLeaveDelay * 1000)) ms")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    // Below ~200 ms the list collapsed out from under a click before it landed.
                    Slider(value: $prefs.hoverLeaveDelay, in: 0.2...1.5, step: 0.05)
                    Text("Short feels twitchy, long feels sticky. 600 ms is the default.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Divider()
                toggle("Click a card to jump", isOn: $prefs.clickToJump, hint: "Off = clicking only selects the session.")
                Divider()
                toggle("Hide island when nothing is running", isOn: $prefs.hideWhenEmpty, hint: "The strip disappears while idle and returns on the next session.")
                    .onChange(of: prefs.hideWhenEmpty) { _, _ in onApplyDisplay() }
                Divider()
                toggle(
                    "Hide in fullscreen",
                    isOn: $prefs.hideInFullscreen,
                    hint: "The strip floats above fullscreen windows. ⌘⇧A still summons the board."
                )
                .onChange(of: prefs.hideInFullscreen) { _, _ in onApplyDisplay() }
            }

            groupBox("Housekeeping") {
                Picker("Idle session cleanup", selection: $prefs.idleCleanupHours) {
                    ForEach(Preferences.idleCleanupChoices, id: \.self) { hours in
                        Text(Preferences.idleCleanupLabel(hours)).tag(hours)
                    }
                }
                .pickerStyle(.menu)
                Text("A running session that has sent no signal for this long lost its process without saying so — mark it ended instead of leaving the dot lit.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            groupBox("New chat") {
                Picker("Default provider for + New", selection: $prefs.defaultNewProvider) {
                    Text("Claude").tag("claude")
                    Text("Grok").tag("grok")
                    Text("OpenCode").tag("opencode")
                    Text("Codex").tag("codex")
                }
                .pickerStyle(.menu)
                Text("Chat Hub must be running (pnpm dev or packaged app).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Integrations

    private var integrationsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("Integrations", subtitle: "Agents and terminals that can appear in the island.")

            groupBox("Sources") {
                integrationRow("Chat Hub", detail: "Claude · Grok · OpenCode · Codex via JSONL bridge", ok: true)
                Divider()
                integrationRow("Claude Code (terminal hooks)", detail: BridgePath.socketDisplayPath + " + events.jsonl", ok: hookInstalled)
                Divider()
                integrationRow("Permission socket", detail: "Blocking Allow/Deny for terminal Claude", ok: socketExists)
            }

            groupBox("Actions") {
                HStack {
                    Button("Install / repair Claude hooks") {
                        runHookInstall()
                    }
                    Button("Reveal bridge folder") {
                        NSWorkspace.shared.open(BridgePath.agentDesktopDir)
                    }
                    Spacer()
                }
                Text(hookInstallResult ?? "Installer: session-monitor/hooks/install.sh")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            groupBox("Coming next") {
                Text("Native Codex / Gemini hooks, more terminal precise-jump (kitty, WezTerm, Ghostty OSC).")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Notifications

    private var notificationsPage: some View {
        @Bindable var notify = notifications
        return VStack(alignment: .leading, spacing: 18) {
            pageTitle("Notifications", subtitle: "macOS banners when agents change state.")
            groupBox("Alert when") {
                toggle("Waiting / needs input", isOn: $prefs.notifyWaiting)
                Divider()
                toggle("Done", isOn: $prefs.notifyDone)
                Divider()
                toggle("Error", isOn: $prefs.notifyError)
            }

            groupBox("Completion") {
                toggle(
                    "Expand panel for completion notifications",
                    isOn: $prefs.expandForCompletion,
                    hint: "Off = the island only glows when a turn finishes. On = it peeks the list open for the auto reveal dwell."
                )
            }

            groupBox("Follow-up") {
                Picker("Remind me again", selection: $notify.followUpMinutes) {
                    ForEach(NotificationSettingsModel.followUpChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? "Off" : "After \(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                Text("Repeats while the session is still waiting, and stops the moment it moves on.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            groupBox("Quiet scenes") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Focus mode", isOn: $notify.quietFocus)
                        .disabled(!QuietScenes.canReadFocusState)
                    if !QuietScenes.canReadFocusState {
                        Text("Unavailable — macOS keeps the Focus state behind Full Disk Access. Grant it in System Settings › Privacy & Security to use this scene.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                toggle("Screen locked or asleep", isOn: $notify.quietScreenLocked)
                Divider()
                toggle(
                    "Screen recording or sharing",
                    isOn: $notify.quietScreenSharing,
                    hint: "Detected from the capture processes macOS runs (⇧⌘5, Screen Sharing, OBS)."
                )
            }

            Text("Quiet scenes silence banners only — the island still lights up, and sounds follow Quiet Hours in Sound.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("System permission is requested on first launch.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Display

    private var displayPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("Display", subtitle: "Island size, notch fit, what each card shows.")

            groupBox("Notch") {
                compactPreview
                Picker("Compact strip", selection: $prefs.compactStyle) {
                    ForEach(CompactStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: prefs.compactStyle) { _, _ in onApplyDisplay() }
                Text(prefs.compactStyle.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            groupBox("Island size") {
                Picker("Width preset", selection: $prefs.widthStyle) {
                    ForEach(Preferences.WidthStyle.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: prefs.widthStyle) { _, _ in onApplyDisplay() }

                Divider()

                slider(
                    "Panel width",
                    value: $prefs.panelWidth,
                    range: 420...820,
                    step: 10,
                    unit: "pt",
                    hint: "Long prompts and paths need room — 420 pt truncated most titles."
                )
                slider(
                    "Max panel height",
                    value: $prefs.maxPanelHeight,
                    range: 260...760,
                    step: 10,
                    unit: "pt",
                    hint: "How tall the list may grow before it scrolls."
                )
                slider(
                    "Content font size",
                    value: $prefs.contentFontSize,
                    range: 11...16,
                    step: 0.5,
                    unit: "pt",
                    hint: "Cards grow with the font, so nothing clips."
                )
            }

            groupBox("Display") {
                Picker("Show on", selection: screenBinding) {
                    Text("Automatic (notch / primary)").tag(String?.none)
                    ForEach(NSScreen.screens, id: \.localizedName) { s in
                        Text(s.localizedName).tag(Optional(s.localizedName))
                    }
                }
                .onChange(of: prefs.screenName) { _, _ in onApplyDisplay() }
            }

            groupBox("Notch tuning") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Notch width offset")
                        Spacer()
                        Text("\(Int(prefs.notchWidthOffset))pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $prefs.notchWidthOffset, in: -40...40, step: 1)
                        .onChange(of: prefs.notchWidthOffset) { _, _ in onApplyDisplay() }

                    HStack {
                        Text("Notch height offset")
                        Spacer()
                        Text("\(Int(prefs.notchHeightOffset))pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $prefs.notchHeightOffset, in: -12...20, step: 1)
                        .onChange(of: prefs.notchHeightOffset) { _, _ in onApplyDisplay() }

                    Text("Fine-tune if the strip doesn’t match your camera cutout. 0 uses the macOS estimate.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            groupBox("Session cards") {
                toggle("Show folder paths", isOn: $prefs.showPathsInRows)
                    .onChange(of: prefs.showPathsInRows) { _, _ in onApplyDisplay() }
                Divider()
                toggle("Show chips (agent · terminal · model)", isOn: $prefs.showStatusChips)
                    .onChange(of: prefs.showStatusChips) { _, _ in onApplyDisplay() }
                Divider()
                toggle("Show last activity line", isOn: $prefs.showActivityDetail)
                    .onChange(of: prefs.showActivityDetail) { _, _ in onApplyDisplay() }
            }
        }
    }

    /// Vibe previews the strip it is about to draw — without it the two style names are just
    /// words. The content is mocked on purpose: Settings has no store, and a real island with
    /// nothing running would preview as an empty bar.
    private var compactPreview: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(hex: 0x2B2D5E), Color(hex: 0x6A3E8F)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            previewStrip(detailed: prefs.compactStyle == .detailed)
        }
        .frame(height: 74)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func previewStrip(detailed: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Circle()
                    .fill(IslandTheme.waiting)
                    .frame(width: IslandTheme.statusDot, height: IslandTheme.statusDot)
                if detailed {
                    Text("proxy-flash")
                        .font(IslandTheme.stripTitleFont)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else {
                    Circle()
                        .fill(IslandTheme.running)
                        .frame(width: IslandTheme.statusDot, height: IslandTheme.statusDot)
                    Circle()
                        .fill(IslandTheme.idle)
                        .frame(width: IslandTheme.statusDot, height: IslandTheme.statusDot)
                }
            }
            .padding(.trailing, 8)
            .frame(width: detailed ? 150 : 74)

            // The camera cutout the strip has to stay clear of.
            Color.clear.frame(width: 96)

            HStack(spacing: 6) {
                if detailed {
                    Text(SessionStatus.waitingInput.label)
                        .font(IslandTheme.stripStatusFont)
                        .foregroundStyle(IslandTheme.statusChipForeground(.waitingInput))
                        .lineLimit(1)
                }
                Text("3")
                    .font(IslandTheme.countFont)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .frame(width: detailed ? 150 : 74)
        }
        .frame(height: 26)
        .background(
            UnevenRoundedRectangle(
                bottomLeadingRadius: IslandTheme.stripBottomRadius,
                bottomTrailingRadius: IslandTheme.stripBottomRadius,
                style: .continuous
            )
            .fill(Color.black)
        )
    }

    // MARK: Sound

    private var soundPage: some View {
        @Bindable var sound = sounds
        return VStack(alignment: .leading, spacing: 18) {
            pageTitle("Sound", subtitle: "Cues when agents start, wait, finish, or fail.")
            groupBox("Playback") {
                toggle("Enable Sound Effects", isOn: $prefs.soundsEnabled)
                HStack {
                    Text("Volume")
                    Slider(value: $prefs.soundVolume, in: 0...1)
                    Text("\(Int(prefs.soundVolume * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40)
                }
                .disabled(!prefs.soundsEnabled)
            }

            ForEach(IslandSounds.Event.Group.allCases) { group in
                groupBox(group.title) {
                    let rows = events(in: group)
                    ForEach(rows, id: \.self) { event in
                        if event != rows.first { Divider() }
                        soundRow(event)
                    }
                }
            }

            groupBox("Quiet Hours") {
                toggle(
                    "Silence during quiet hours",
                    isOn: $sound.quietHoursEnabled,
                    hint: "Banners still arrive — this only mutes the cues."
                )
                if sound.quietHoursEnabled {
                    HStack(spacing: 16) {
                        DatePicker(
                            "From",
                            selection: timeBinding($sound.quietFromMinutes),
                            displayedComponents: .hourAndMinute
                        )
                        DatePicker(
                            "To",
                            selection: timeBinding($sound.quietToMinutes),
                            displayedComponents: .hourAndMinute
                        )
                        Spacer()
                    }
                }
            }
        }
    }

    private func events(in group: IslandSounds.Event.Group) -> [IslandSounds.Event] {
        IslandSounds.Event.allCases.filter { $0.group == group }
    }

    private func soundRow(_ event: IslandSounds.Event) -> some View {
        let selection = Binding(
            get: { sounds[event] },
            set: { sounds[event] = $0 }
        )
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                Text(event.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: selection) {
                Text("Off").tag(IslandSounds.off)
                ForEach(sounds.options(for: event), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            Button {
                IslandSounds.preview(event)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .disabled(selection.wrappedValue == IslandSounds.off)
            .help("Preview")
        }
    }

    /// The picker stores a wall-clock minute of day; DatePicker wants a Date on some day.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: minutes.wrappedValue / 60,
                    minute: minutes.wrappedValue % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    // MARK: Usage

    private var usagePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("Usage", subtitle: "Rate limits and spend — planned.")
            groupBox("Status") {
                Text("Usage tracking (Claude / Codex / …) is on the roadmap. Vibe uses a statusline + offline price table; we’ll mirror that without cloud accounts.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Shortcuts

    private var shortcutsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("Shortcuts", subtitle: "Global hotkeys.")
            groupBox("Island") {
                shortcutRow("Toggle expanded board", keys: "⌘⇧A")
                Divider()
                shortcutRow("Collapse", keys: "Esc")
                Divider()
                shortcutRow("Menu bar", keys: "Click icon · right-click for menu")
            }
            groupBox("Accessibility") {
                integrationRow(
                    escWorksGlobally ? "Accessibility: Granted" : "Accessibility: Not granted",
                    detail: escWorksGlobally
                        ? "Global Esc and the click-outside collapse are active from any app."
                        : "Global Esc won't fire outside the island until this is granted.",
                    ok: escWorksGlobally
                )
                if !escWorksGlobally {
                    Button("Open System Settings › Privacy & Security › Accessibility") {
                        openAccessibilitySettings()
                    }
                }
            }
        }
    }

    /// A global key monitor gets nothing without the Accessibility grant, so the Esc row
    /// above is a half-truth until it is given. Query-only (no prompt) — the prompting
    /// call lives in AppController.requestAccessibilityIfNeeded() at startup.
    private var escWorksGlobally: Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: SSH

    private var sshPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("SSH Remote", subtitle: "Agents on remote machines.")
            groupBox("Status") {
                Text("SSH remote hooks + tunnel are planned (Labs flag available). Not enabled in this build.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Toggle("Enable experimental SSH UI", isOn: $prefs.experimentalSSH)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: Labs

    private var labsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("Labs", subtitle: "Experimental features.")
            groupBox("Experiments") {
                toggle("Tool cards from PostToolUse", isOn: $prefs.experimentalToolCards, hint: "Flag only — card rendering does not read it in this build.")
                Divider()
                toggle("SSH Remote UI shell", isOn: $prefs.experimentalSSH)
            }
        }
    }

    // MARK: About

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("About", subtitle: "Session Monitor — Agent Desktop Suite.")
            groupBox("Version") {
                LabeledContent("App") { Text(appVersion) }
                LabeledContent("Bundle") { Text("com.agentdesktop.SessionMonitor") }
                // The only way to tell whether /Applications is running the tree in front of you.
                LabeledContent("Build") { Text("\(BuildInfo.revision) · \(BuildInfo.builtAt)") }
            }
            groupBox("Paths") {
                pathRow("Events", BridgePath.displayPath)
                pathRow("Commands", BridgePath.commandsFile.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                pathRow("Socket", BridgePath.socketDisplayPath)
            }
            groupBox("Diagnostics") {
                HStack {
                    Button("Export Diagnostic Report…") { exportDiagnostics() }
                    Button("Copy build identity") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(BuildInfo.summary, forType: .string)
                    }
                    Spacer()
                }
                Text(diagnosticResult ?? "Includes system information and the recent bridge log. Session titles, prompts and paths are stripped — review the file before sharing.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Reveal data folder") {
                    NSWorkspace.shared.open(BridgePath.agentDesktopDir)
                }
                Button("Quit Session Monitor") { onQuit() }
                Spacer()
            }
        }
    }

    private func exportDiagnostics() {
        diagnosticResult = "Collecting…"
        let screens = NSScreen.screens.map {
            "\($0.localizedName) \(Int($0.frame.width))×\(Int($0.frame.height)) @\($0.backingScaleFactor)x"
        }
        Task {
            let report = await Self.buildDiagnosticReport(screens: screens)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "SessionMonitor-diagnostics.txt"
            panel.allowedContentTypes = [.plainText]
            guard panel.runModal() == .OK, let url = panel.url else {
                diagnosticResult = "Export cancelled."
                return
            }
            do {
                try report.write(to: url, atomically: true, encoding: .utf8)
                diagnosticResult = "Saved to \(url.lastPathComponent) — review it before sharing."
            } catch {
                diagnosticResult = "Could not write the report — \(error.localizedDescription)"
            }
        }
    }

    /// Off the main actor: it stats and tails the bridge log, which is unbounded between rotations.
    /// Redaction is a whitelist, not a blacklist — an event key we never taught it about must not
    /// leak a prompt into a file the user is about to paste into an issue.
    nonisolated private static func buildDiagnosticReport(screens: [String]) async -> String {
        await Task.detached { () -> String in
            var lines = [
                "Session Monitor diagnostic report",
                "Generated: \(ISO8601DateFormatter().string(from: Date()))",
                "",
                "## App",
                "Version: \(BuildInfo.summary)",
                "Bundle: com.agentdesktop.SessionMonitor",
                "Path: \(Bundle.main.bundlePath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))",
                "",
                "## System",
                "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
                "Model: \(Self.sysctlString("hw.model"))",
                "Screens: \(screens.joined(separator: " · "))",
                "",
                "## Settings",
            ]

            let prefixes = ["general.", "display.", "island.", "notify.", "sound", "labs."]
            let stored = UserDefaults.standard.dictionaryRepresentation()
                .filter { key, _ in prefixes.contains { key.hasPrefix($0) } }
            for key in stored.keys.sorted() {
                lines.append("\(key) = \(String(describing: stored[key] ?? ""))")
            }

            lines.append(contentsOf: ["", "## Bridge"])
            for (label, url) in [
                ("events", BridgePath.eventsFile),
                ("commands", BridgePath.commandsFile),
                ("socket", BridgePath.socketFile),
            ] {
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? Int).map { "\($0) bytes" } ?? "missing"
                lines.append("\(label): \(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) — \(size)")
            }

            lines.append(contentsOf: ["", "## Recent events (redacted)"])
            lines.append(contentsOf: Self.redactedEventTail(limit: 60))
            return lines.joined(separator: "\n") + "\n"
        }.value
    }

    /// Reads only the tail: the bridge log grows to megabytes and the last minutes are the only
    /// part a bug report needs.
    nonisolated private static func redactedEventTail(limit: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: BridgePath.eventsFile) else {
            return ["(no events.jsonl)"]
        }
        defer { try? handle.close() }
        let window = UInt64(256 * 1024)
        let end = (try? handle.seekToEnd()) ?? 0
        let truncated = end > window
        try? handle.seek(toOffset: truncated ? end - window : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        let keep: Set<String> = ["type", "event", "sessionId", "id", "provider", "status", "model", "source", "ts", "reason", "requestId"]
        let rows = String(decoding: data, as: UTF8.self).split(separator: "\n")
        // Seeking into the middle of the file leaves a half line at the front.
        return rows.dropFirst(truncated ? 1 : 0)
            .suffix(limit)
            .map { line in
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                    return "(unparsed line)"
                }
                let fields = obj.keys.sorted()
                    .filter { keep.contains($0) }
                    .map { "\($0)=\(String(describing: obj[$0] ?? ""))" }
                return fields.joined(separator: " ")
            }
    }

    nonisolated private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    // MARK: - Helpers

    private var screenBinding: Binding<String?> {
        Binding(
            get: { prefs.screenName },
            set: { prefs.screenName = $0 }
        )
    }

    private var hookInstalled: Bool {
        let p = NSHomeDirectory() + "/.claude/settings.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: p)),
              let s = String(data: data, encoding: .utf8)
        else { return false }
        return s.contains("agent-desktop-claude-hook")
    }

    private var socketExists: Bool {
        FileManager.default.fileExists(atPath: BridgePath.socketFile.path)
    }

    private var appVersion: String {
        "\(BuildInfo.version) (\(BuildInfo.build))"
    }

    /// Labelled slider with a live readout — the island re-lays out as you drag.
    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(step < 1 ? String(format: "%.1f%@", value.wrappedValue, unit)
                              : "\(Int(value.wrappedValue))\(unit)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
                .onChange(of: value.wrappedValue) { _, _ in onApplyDisplay() }
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func groupBox(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: isOn)
            if let hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func integrationRow(_ title: String, detail: String, ok: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func shortcutRow(_ title: String, keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
    }

    private func pathRow(_ label: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text(path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
        }
    }

    /// Prefer the copy shipped in the bundle — once installed to /Applications the repo
    /// may not be on the Desktop at all. The whole `hooks` folder ships, not just this
    /// script: it registers a command line pointing at its own sibling .py, and running a
    /// lone install.sh would write a hook path that does not exist.
    private var hookInstallScript: URL? {
        if let bundled = Bundle.main.url(forResource: "install", withExtension: "sh", subdirectory: "hooks") {
            return bundled
        }
        let dev = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop/agent-desktop-suite/session-monitor/hooks/install.sh")
        return FileManager.default.isReadableFile(atPath: dev.path) ? dev : nil
    }

    private func runHookInstall() {
        guard let script = hookInstallScript else {
            hookInstallResult = "install.sh not found — run session-monitor/hooks/install.sh from the repo."
            return
        }
        hookInstallResult = "Running install.sh…"
        let path = script.path
        Task {
            hookInstallResult = await Self.runInstaller(at: path)
        }
    }

    /// Off the main actor and awaited: the script rewrites ~/.claude/settings.json, and a
    /// fire-and-forget `try?` hid both launch failures and a non-zero exit.
    nonisolated private static func runInstaller(at path: String) async -> String {
        await Task.detached { () -> String in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [path]
            let errPipe = Pipe()
            p.standardError = errPipe
            // Null, not a Pipe: an undrained stdout pipe would stall the script.
            p.standardOutput = FileHandle.nullDevice
            do { try p.run() } catch {
                return "Could not run install.sh — \(error.localizedDescription)"
            }
            // Drain before waiting: a full pipe would block the script forever.
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                let detail = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return "install.sh failed (exit \(p.terminationStatus))" + (detail.isEmpty ? "" : ": \(detail)")
            }
            return "Hooks installed — restart Claude Code sessions to pick them up."
        }.value
    }
}
