import AppKit
import SwiftUI

struct VibeIslandView: View {
    @Bindable var store: SessionStore
    @Bindable var ui: IslandUIState
    @Bindable var prefs: Preferences
    var commands: CommandBridge
    var bridgePath: String
    var onSizeChange: (CGSize) -> Void
    var onQuit: () -> Void

    private var currentSize: CGSize {
        let scale = prefs.widthStyle.scale
        switch ui.mode {
        case .tucked:
            return CGSize(width: 120, height: 22)
        case .pill:
            return CGSize(width: ((store.waitingCount > 0 ? 176 : 148) * scale).rounded(), height: 24)
        case .expanded:
            return CGSize(width: (392 * scale).rounded(), height: 448)
        }
    }

    var body: some View {
        Group {
            switch ui.mode {
            case .tucked:
                tuckedIsland
            case .pill:
                pillIsland
            case .expanded:
                expandedIsland
            }
        }
        .frame(width: currentSize.width, height: currentSize.height, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: ui.mode)
        .onAppear { onSizeChange(currentSize) }
        .onChange(of: ui.mode) { _, _ in onSizeChange(currentSize) }
        .onChange(of: prefs.widthStyle) { _, _ in onSizeChange(currentSize) }
        .onChange(of: store.waitingCount) { _, count in
            if count > 0, ui.mode == .tucked {
                ui.mode = .pill
            }
        }
        .onExitCommand {
            if ui.mode == .expanded {
                ui.collapseToPill()
            } else if ui.mode == .pill {
                ui.tuck()
            }
        }
    }

    // MARK: - Tucked

    private var tuckedIsland: some View {
        Button {
            ui.mode = store.waitingCount > 0 || hasLive ? .pill : .expanded
        } label: {
            HStack(spacing: 6) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 4)
                if store.waitingCount > 0 {
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CurtainShell(topRadius: 0, bottomRadius: 10, emphasize: store.waitingCount > 0))
        }
        .buttonStyle(.plain)
        .help("Session Monitor")
    }

    // MARK: - Pill

    private var pillIsland: some View {
        Button {
            ui.expand()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))

                HStack(spacing: -3) {
                    ForEach(collapsedDots.prefix(3)) { session in
                        Circle()
                            .fill(color(for: session.status))
                            .frame(width: 6, height: 6)
                            .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 0.8))
                    }
                }

                // Number = sessions waiting for your input (real agents only).
                if store.waitingCount > 0 {
                    Text("\(store.waitingCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.9)))
                } else if liveCount > 0 {
                    Text("\(liveCount)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CurtainShell(topRadius: 0, bottomRadius: 12, emphasize: store.waitingCount > 0))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Expand") { ui.expand() }
            Button("Hide") { ui.tuck() }
            Divider()
            Button("Quit") { onQuit() }
        }
        .help("Badge = agents waiting for input · ⌘⇧A expand")
    }

    // MARK: - Expanded

    private var expandedIsland: some View {
        VStack(spacing: 0) {
            dragHandle
            header
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
            footer
        }
        .background(CurtainShell(topRadius: 0, bottomRadius: 22, emphasize: store.waitingCount > 0))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 22,
                bottomTrailingRadius: 22,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
    }

    private var dragHandle: some View {
        Button {
            ui.collapseToPill()
        } label: {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 34, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sessions")
                    .font(.system(size: 13, weight: .semibold))
                Text(
                    store.waitingCount > 0
                        ? "\(store.waitingCount) waiting for input"
                        : "Live from Chat Hub"
                )
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Button {
                ui.tuck()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(6)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(IslandUIState.SessionFilter.allCases, id: \.self) { option in
                Button {
                    ui.filter = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(ui.filter == option ? 0.95 : 0.45))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.white.opacity(ui.filter == option ? 0.14 : 0.05))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var sessionList: some View {
        Group {
            if filteredSessions.isEmpty {
                VStack(spacing: 6) {
                    Text(emptyTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Start a chat in Chat Hub — it appears here")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 5) {
                        ForEach(filteredSessions) { session in
                            IslandSessionRow(
                                session: session,
                                selected: ui.selectedSessionId == session.id
                            ) {
                                ui.selectedSessionId = session.id
                                store.openChat(sessionId: session.id, commands: commands)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
                .frame(maxHeight: selectedSession?.status == .waitingInput ? 160 : 240)
            }
        }
    }

    @ViewBuilder
    private func detailPane(_ session: SessionMeta) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    store.openChat(sessionId: session.id, commands: commands)
                } label: {
                    Label(
                        session.openActionLabel,
                        systemImage: session.isTerminalSession ? "terminal" : "arrow.up.right.square"
                    )
                    .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.75))
                .disabled(session.isMock)
            }

            if session.status == .waitingInput {
                Text(session.pending?.promptText ?? "Waiting for your input")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                if session.isTerminalSession {
                    // v1: terminal sessions are monitor-only — reply happens in the terminal.
                    Button {
                        store.openChat(sessionId: session.id, commands: commands)
                    } label: {
                        Text("Switch to terminal to respond →")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                } else if let options = session.pending?.options, !options.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(options, id: \.self) { option in
                            Button(option) {
                                store.answer(
                                    sessionId: session.id,
                                    text: option,
                                    commands: commands
                                )
                                ui.draftReply = ""
                            }
                            .buttonStyle(IslandChipButton(destructive: option.lowercased() == "deny"))
                        }
                    }
                }

                if !session.isTerminalSession {
                HStack(spacing: 8) {
                    TextField("Reply…", text: $ui.draftReply)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                        .onSubmit { sendDraft(for: session) }

                    Button {
                        sendDraft(for: session)
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.9)))
                    }
                    .buttonStyle(.plain)
                    .disabled(ui.draftReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                }
            } else if !session.isMock {
                Text("Click row or Open in Hub to jump to this chat")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                Text("Demo session — enable SESSION_MONITOR_MOCK=1 only for UI tests")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    private var footer: some View {
        HStack {
            Text("⌘⇧A · Esc · number = waiting")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.28))
            Spacer()
            Button("Quit") { onQuit() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sendDraft(for session: SessionMeta) {
        let text = ui.draftReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.answer(sessionId: session.id, text: text, commands: commands)
        ui.draftReply = ""
    }

    private var filteredSessions: [SessionMeta] {
        store.islandSessions(filter: ui.filter)
    }

    private var emptyTitle: String {
        switch ui.filter {
        case .waiting: "Nothing waiting on you"
        case .all: "No agent sessions yet"
        case .live: "No active sessions"
        }
    }

    private var selectedSession: SessionMeta? {
        guard let id = ui.selectedSessionId else {
            return filteredSessions.first { $0.status == .waitingInput } ?? filteredSessions.first
        }
        return store.sessions.first { $0.id == id } ?? filteredSessions.first
    }

    private var collapsedDots: [SessionMeta] { store.islandSessions }

    private var liveCount: Int {
        store.islandSessions.filter(\.status.isLive).count
    }

    private var hasLive: Bool { liveCount > 0 }

    private var leadingSymbol: String {
        if store.waitingCount > 0 { return "bell.fill" }
        if hasLive { return "waveform" }
        return "circle.grid.2x1.fill"
    }

    private func color(for status: SessionStatus) -> Color {
        switch status {
        case .running: Color.white.opacity(0.72)
        case .waitingInput: Color.white.opacity(0.95)
        case .error: Color.white.opacity(0.45)
        case .done: Color.white.opacity(0.22)
        case .idle: Color.white.opacity(0.18)
        }
    }
}

struct IslandSessionRow: View {
    let session: SessionMeta
    var selected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 26, height: 26)
                    Image(systemName: providerSymbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(session.provider.capitalized)
                            .foregroundStyle(.white.opacity(0.5))
                        Text("·").foregroundStyle(.white.opacity(0.2))
                        Text(shortPath(session.cwd))
                            .foregroundStyle(.white.opacity(0.32))
                            .lineLimit(1)
                    }
                    .font(.system(size: 10))
                }

                Spacer(minLength: 4)

                Text(session.status.label)
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.white.opacity(statusOpacity))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected || session.status == .waitingInput
                          ? Color.white.opacity(0.09)
                          : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        Color.white.opacity(
                            session.status == .waitingInput ? 0.22 : (selected ? 0.12 : 0.05)
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open in Chat Hub") { onSelect() }
            Button("Copy session ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            }
            if let cwd = session.cwd, !cwd.isEmpty {
                Button("Reveal project") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
                }
            }
        }
    }

    private var statusOpacity: Double {
        switch session.status {
        case .waitingInput: 0.9
        case .running: 0.7
        case .error: 0.55
        default: 0.4
        }
    }

    private var providerSymbol: String {
        switch session.provider.lowercased() {
        case "grok": "sparkles"
        case "claude": "brain.head.profile"
        case "codex": "chevron.left.forwardslash.chevron.right"
        case "opencode": "terminal"
        default: "bubble.left.and.bubble.right.fill"
        }
    }

    private func shortPath(_ cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "—" }
        let parts = cwd.split(separator: "/").map(String.init)
        if parts.count <= 2 { return cwd }
        return "…/" + parts.suffix(2).joined(separator: "/")
    }
}

private struct IslandChipButton: ButtonStyle {
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white.opacity(destructive ? 0.55 : 0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(Color.white.opacity(destructive ? 0.06 : 0.1))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct CurtainShell: View {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var emphasize: Bool

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        )
        ZStack {
            shape.fill(Color.black.opacity(0.97))
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.02),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            shape.stroke(Color.white.opacity(emphasize ? 0.16 : 0.09), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }
}
