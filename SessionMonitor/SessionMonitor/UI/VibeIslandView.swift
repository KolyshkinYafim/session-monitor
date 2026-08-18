import AppKit
import SwiftUI

/// Vibe-like island:
/// - **compact**: short black strip — dots left of notch, **count right** (always readable)
/// - **activity** (hover): wider board with session cards + **+ New**
/// - **expanded** (⌘⇧A): full board + filters + Allow/Deny / reply
struct VibeIslandView: View {
    @Bindable var store: SessionStore
    @Bindable var ui: IslandUIState
    @Bindable var prefs: Preferences
    var commands: CommandBridge
    var bridgePath: String
    var onExpand: () -> Void
    var onCollapse: () -> Void
    var onCompact: () -> Void
    /// Click on the compact strip — opens the list even when hover peek is off.
    var onOpenList: () -> Void
    var onQuit: () -> Void
    var onHoverChange: (Bool) -> Void

    /// Published by the controller so a display change re-lays out the strip; the local
    /// computation is only a fallback for the first frame.
    private var metrics: IslandGeometry.Metrics {
        if let published = ui.metrics { return published }
        let screen = IslandGeometry.dockingScreen(preferredName: prefs.screenName)
        return screen.map {
            IslandGeometry.metrics(
                for: $0,
                notchWidthOffset: CGFloat(prefs.notchWidthOffset),
                notchHeightOffset: CGFloat(prefs.notchHeightOffset)
            )
        } ?? IslandGeometry.Metrics(menuBarHeight: 40, notchWidth: IslandTheme.defaultNotchWidth, hasNotch: true)
    }

    /// Same count the panel is sized for — drawing more would clip the cards and the
    /// "+ New" button off the bottom edge.
    private var displaySessions: [SessionMeta] {
        Array(store.islandSessions.prefix(IslandGeometry.visibleRows(prefs: prefs)))
    }

    private var liveCount: Int {
        store.islandSessions.filter(\.status.isLive).count
    }

    private var visibleWaiting: Int {
        store.islandSessions.filter { $0.status == .waitingInput }.count
    }

    /// Live + recently-finished — what the board actually lists. Never labelled "active":
    /// `islandSessions` keeps a session around for minutes after it said Done.
    private var recentCount: Int {
        store.islandSessions.count
    }

    var body: some View {
        Group {
            switch ui.mode {
            case .compact:
                compactStrip
            case .activity:
                hoverBoard
            case .expanded:
                expandedBoard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .onExitCommand {
            if ui.mode == .expanded { onCollapse() }
            else { onCompact() }
        }
    }

    // MARK: - Compact strip (Vibe default)

    private var compactStrip: some View {
        Button {
            onOpenList()
        } label: {
            notchStrip(count: liveCount, sessions: displaySessions, style: prefs.compactStyle)
                .frame(height: metrics.stripHeight)
                .background(Shell(corner: IslandTheme.stripBottomRadius, pulsing: ui.attentionPulse))
        }
        .buttonStyle(.plain)
        .help("Hover or click · ⌘⇧A expand")
        .contextMenu { ctxMenu }
    }

    /// The session the Detailed strip speaks for: whoever needs the user first, else the
    /// top card. A strip naming a running session while another one waits would point
    /// the eye at the wrong window.
    private var headlineSession: SessionMeta? {
        displaySessions.first { $0.status == .waitingInput } ?? displaySessions.first
    }

    /// Left wing dots (or Detailed title) · empty notch · right wing **big count**.
    private func notchStrip(count: Int, sessions: [SessionMeta], style: CompactStyle) -> some View {
        // Derived from the panel width the controller sized, so a Detailed wing clamped
        // to the menu bar budget still stops short of the camera housing.
        let wing = IslandGeometry.stripWingWidth(
            metrics: metrics,
            scale: prefs.widthStyle.scale,
            style: style
        )
        let headline = style == .detailed ? headlineSession : nil
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            // LEFT — status dots, padded away from the camera edge
            HStack(spacing: 5) {
                Spacer(minLength: 0)
                if let headline {
                    Circle()
                        .fill(IslandTheme.statusColor(headline.status))
                        .frame(width: IslandTheme.statusDot, height: IslandTheme.statusDot)
                    Text(headline.title)
                        .font(IslandTheme.stripTitleFont)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if sessions.isEmpty {
                    Image(systemName: "circle.grid.2x1.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    ForEach(sessions.prefix(3)) { s in
                        Circle()
                            .fill(IslandTheme.statusColor(s.status))
                            .frame(width: IslandTheme.statusDot, height: IslandTheme.statusDot)
                    }
                }
            }
            .padding(.trailing, 6)
            .frame(width: wing)

            Color.clear
                .frame(width: metrics.notchWidth)

            // RIGHT — count always visible, padded from camera
            HStack(spacing: 5) {
                if let headline {
                    Text(headline.status.label)
                        .font(IslandTheme.stripStatusFont)
                        .foregroundStyle(IslandTheme.statusChipForeground(headline.status))
                        .lineLimit(1)
                }
                Text(count > 0 ? "\(count)" : "·")
                    .font(IslandTheme.countFont)
                    .foregroundStyle(count > 0 ? Color.white : Color.white.opacity(0.3))
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
            .frame(width: wing)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Hover board

    private var hoverBoard: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: metrics.stripHeight)
                .overlay {
                    // Mini strip: dots + count still visible while list is open. It always
                    // uses the Clean style, because the board is sized from `panelWidth`,
                    // not from the menu bar budget — Detailed wings would not line up with
                    // it, and the title Detailed would carry is already the first card
                    // underneath.
                    notchStrip(count: liveCount, sessions: displaySessions, style: .clean)
                        .opacity(0.95)
                }

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(visibleWaiting > 0 ? "\(visibleWaiting) need you" : "\(liveCount) active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(visibleWaiting > 0 ? IslandTheme.waiting : .white.opacity(0.5))
                    Spacer()
                    Button {
                        // Open settings via notification to AppController/status item path
                        NotificationCenter.default.post(name: .sessionMonitorOpenSettings, object: nil)
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Settings (sound, notch, notifications)")
                }
                .padding(.horizontal, 4)

                // Cards scroll rather than overflow: a card that is a few points taller
                // than estimated must not push "+ New" past the panel's bottom edge.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(displaySessions) { session in
                            VStack(spacing: 6) {
                                HoverSessionRow(
                                    session: session,
                                    showChips: prefs.showStatusChips,
                                    showActivity: prefs.showActivityDetail,
                                    showPath: prefs.showPathsInRows,
                                    fontSize: CGFloat(prefs.contentFontSize)
                                ) {
                                    ui.selectedSessionId = session.id
                                    open(session)
                                }
                                // Approving is the reason the island exists — never make the user
                                // press ⌘⇧A to reach the buttons.
                                if session.status == .waitingInput, let pending = session.pending {
                                    pendingActions(session: session, pending: pending)
                                }
                            }
                        }
                        if displaySessions.isEmpty {
                            Text("No live sessions")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)

                Button(action: newChat) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("New")
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .frame(height: IslandTheme.newButtonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, IslandTheme.listPad)
            .padding(.bottom, 10)
            .padding(.top, 4)
        }
        .background(Shell(corner: IslandTheme.panelCorner))
        .contextMenu { ctxMenu }
    }

    /// Inline decision row: what is being asked, and the answers, one click away.
    @ViewBuilder
    private func pendingActions(session: SessionMeta, pending: PendingInteraction) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isPermission(pending) ? "lock.shield" : "questionmark.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IslandTheme.waiting)
            Text(pending.promptText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            // No chip we cannot honour: a terminal `session.question` has no reply channel,
            // and a permission whose hook already went away answers nobody.
            let options = store.canAnswer(session) ? chipOptions(for: pending) : []
            if options.isEmpty {
                Text(store.canAnswer(session) ? "⌘⇧A to reply" : "answer in terminal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        store.answer(sessionId: session.id, text: option, commands: commands)
                    }
                    .buttonStyle(ChipStyle(destructive: isDeny(option)))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(IslandTheme.waiting.opacity(0.10))
        )
    }

    /// Allow/Deny is the permission protocol, not a default: a question with no options
    /// expects free text, and inventing two buttons for it sends a word nobody asked for.
    private func chipOptions(for pending: PendingInteraction) -> [String] {
        if isPermission(pending) { return pending.options ?? ["Allow", "Deny"] }
        return pending.options ?? []
    }

    private func isPermission(_ pending: PendingInteraction) -> Bool {
        if case .permission = pending { return true }
        return false
    }

    private func isDeny(_ option: String) -> Bool {
        ["deny", "no", "reject", "cancel"].contains(option.lowercased())
    }

    // MARK: - Expanded

    private var expandedBoard: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.stripHeight)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sessions")
                        .font(IslandTheme.titleFont)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(visibleWaiting > 0 ? IslandTheme.waiting : .white.opacity(0.45))
                }
                Spacer()
                Button(action: onCollapse) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            filterBar
            sessionList
            if let selected = selectedSession {
                detailPane(selected)
            }
            if let msg = store.lastOpenResult {
                Text(msg)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            Button(action: newChat) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("New chat in Hub")
                    Spacer()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            footer
        }
        .background(Shell(corner: IslandTheme.panelCorner))
    }

    private var subtitle: String {
        if visibleWaiting > 0 {
            return "\(visibleWaiting) waiting · \(liveCount) live · \(recentCount) recent"
        }
        return "\(liveCount) live · \(recentCount) recent"
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(IslandUIState.SessionFilter.allCases, id: \.self) { option in
                filterChip(option.rawValue, selected: ui.filter == option) { ui.filter = option }
            }
            // Status and origin are independent picks. Without a break the six capsules read
            // as one six-way choice, and two of them look lit at once for no reason.
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 12)
                .padding(.horizontal, 2)
            ForEach(IslandUIState.SourceFilter.allCases, id: \.self) { option in
                filterChip(option.rawValue, selected: ui.sourceFilter == option) {
                    ui.sourceFilter = option
                }
            }
            Spacer()
            Text("\(filteredSessions.count)")
                .font(IslandTheme.countFont)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func filterChip(
        _ label: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(selected ? 0.95 : 0.45))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.14 : 0.05)))
        }
        .buttonStyle(.plain)
    }

    private var sessionList: some View {
        Group {
            if filteredSessions.isEmpty {
                Text("No sessions — New chat or start Claude in Terminal")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(24)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredSessions) { session in
                            HoverSessionRow(
                                session: session,
                                selected: ui.selectedSessionId == session.id,
                                showChips: prefs.showStatusChips,
                                showActivity: prefs.showActivityDetail,
                                showPath: prefs.showPathsInRows,
                                fontSize: CGFloat(prefs.contentFontSize)
                            ) {
                                ui.selectedSessionId = session.id
                                open(session)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                // The list is the only elastic part of the board: it yields whatever the
                // detail pane, reply field, CTA and footer need instead of pushing them
                // outside the panel, where they simply aren't drawn.
                .frame(maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func detailPane(_ session: SessionMeta) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Button { open(session) } label: {
                    Label(session.openActionLabel, systemImage: session.isTerminalSession ? "terminal" : "arrow.up.right.square")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.8))
                .disabled(session.isMock)
            }

            if session.status == .waitingInput {
                Text(session.pending?.promptText ?? "Waiting for input")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))

                if let pending = session.pending, store.canAnswer(session) {
                    let options = chipOptions(for: pending)
                    if !options.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(options, id: \.self) { option in
                                Button(option) {
                                    store.answer(sessionId: session.id, text: option, commands: commands)
                                }
                                .buttonStyle(ChipStyle(destructive: isDeny(option)))
                            }
                        }
                    }
                } else if session.isTerminalSession {
                    Text("Only the terminal can answer this one.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }

                if !session.isTerminalSession {
                    HStack(spacing: 8) {
                        TextField("Reply…", text: $ui.draftReply)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
                            .onSubmit { sendDraft(session) }
                        Button { sendDraft(session) } label: {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(.black)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(IslandTheme.waiting))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
    }

    private var footer: some View {
        HStack {
            Text("⌘⇧A · Esc · hover to peek")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.28))
            Spacer()
            Button("Quit") { onQuit() }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder private var ctxMenu: some View {
        Button("Expand") { onExpand() }
        Button("Compact") { onCompact() }
        Button("New chat") { newChat() }
        Divider()
        Button("Quit") { onQuit() }
    }

    private func open(_ session: SessionMeta) {
        guard prefs.clickToJump else {
            store.setOpenResult("Click-to-jump is off — enable it in Settings › General")
            return
        }
        store.openChat(sessionId: session.id, commands: commands)
    }

    private func newChat() {
        let ok = commands.newSession(provider: prefs.defaultNewProvider)
        store.setOpenResult(
            ok
                ? "Opening Chat Hub — new session…"
                : "Start Chat Hub (pnpm dev) to create sessions"
        )
    }

    private func sendDraft(_ session: SessionMeta) {
        let t = ui.draftReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store.answer(sessionId: session.id, text: t, commands: commands)
        ui.draftReply = ""
    }

    private var filteredSessions: [SessionMeta] {
        store.islandSessions(filter: ui.filter, source: ui.sourceFilter)
    }

    private var selectedSession: SessionMeta? {
        if let id = ui.selectedSessionId, let s = store.sessions.first(where: { $0.id == id }) { return s }
        return filteredSessions.first { $0.status == .waitingInput } ?? filteredSessions.first
    }
}

// MARK: - Rows (product card — project · host · CLI · model · age · open/closed)

private struct HoverSessionRow: View {
    let session: SessionMeta
    var selected: Bool = false
    var showChips: Bool = true
    var showActivity: Bool = true
    var showPath: Bool = false
    /// Base point size from Settings → Display; every line scales off it.
    var fontSize: CGFloat = 12.5
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                // Line 1: status dot · project · title fragment · chips · age
                HStack(spacing: 8) {
                    Circle()
                        .fill(IslandTheme.statusColor(session.status))
                        .frame(width: 8, height: 8)
                        .opacity(session.isClosed ? 0.35 : 1)

                    Text(session.projectLabel)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(session.isClosed ? 0.45 : 0.95))
                        .lineLimit(1)
                        .layoutPriority(2)

                    if !session.displayTitle.isEmpty, session.displayTitle != session.projectLabel {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.25))
                        Text(session.displayTitle)
                            .font(.system(size: fontSize - 0.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                    }

                    Spacer(minLength: 4)

                    if showChips {
                        HStack(spacing: 6) {
                            if session.showsProviderChip {
                                chip(session.providerLabel, color: IslandTheme.providerColor(session.provider))
                            }
                            chip(session.hostLabel, color: .white.opacity(0.7))
                            if let model = session.model, !model.isEmpty {
                                chip(shortModel(model), color: .white.opacity(0.55))
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(3)
                    }
                    Text(session.relativeAge())
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .monospacedDigit()
                }

                // Line 2: Ready / Running / Closed + last activity
                HStack(spacing: 8) {
                    Text(session.displayStatus)
                        .font(.system(size: fontSize - 1.5, weight: .semibold))
                        .foregroundStyle(statusColor)

                    if session.isClosed {
                        Text("· chat closed")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    } else if showActivity, let activity = session.lastActivity, !activity.isEmpty {
                        Text(activity)
                            .font(.system(size: fontSize - 1.5))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }

                if showPath, let cwd = session.cwd, !cwd.isEmpty {
                    Text(shortPath(cwd))
                        .font(.system(size: fontSize - 2.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: IslandTheme.rowCorner, style: .continuous)
                    .fill(
                        session.status == .waitingInput || selected
                            ? Color.white.opacity(0.09)
                            : Color.white.opacity(0.045)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: IslandTheme.rowCorner, style: .continuous)
                    .stroke(
                        session.isClosed
                            ? Color.white.opacity(0.04)
                            : (session.status == .waitingInput
                                ? IslandTheme.waiting.opacity(0.35)
                                : Color.clear),
                        lineWidth: 1
                    )
            )
            .opacity(session.isClosed ? 0.75 : 1)
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        if session.isClosed { return .white.opacity(0.4) }
        return IslandTheme.statusChipForeground(session.status)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func shortModel(_ model: String) -> String {
        // claude-sonnet-4-20250514 → sonnet-4
        let parts = model.split(separator: "-").map(String.init)
        if parts.count >= 2 {
            let interesting = parts.filter { !["claude", "gpt", "openai", "google"].contains($0.lowercased()) }
            return interesting.prefix(2).joined(separator: "-")
        }
        return String(model.prefix(12))
    }
}

struct IslandSessionRow: View {
    let session: SessionMeta
    var selected: Bool
    var onSelect: () -> Void
    var body: some View {
        HoverSessionRow(session: session, selected: selected, onSelect: onSelect)
    }
}

// MARK: - Shell

private struct Shell: View {
    var corner: CGFloat
    /// Ambient cue when an agent needs the user and the island stays collapsed.
    var pulsing: Bool = false
    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: corner,
            bottomTrailingRadius: corner,
            topTrailingRadius: 0,
            style: .continuous
        )
        shape.fill(IslandTheme.shellFill.opacity(0.97))
            .overlay(shape.stroke(IslandTheme.waiting.opacity(pulsing ? 0.9 : 0), lineWidth: 2))
            .shadow(color: pulsing ? IslandTheme.waiting.opacity(0.35) : .black.opacity(0.5), radius: 20, y: 10)
            .animation(.easeOut(duration: 0.25), value: pulsing)
    }
}

private struct ChipStyle: ButtonStyle {
    var destructive: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(destructive ? Color.white.opacity(0.55) : IslandTheme.waiting)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(destructive ? Color.white.opacity(0.06) : IslandTheme.waiting.opacity(0.14)))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
