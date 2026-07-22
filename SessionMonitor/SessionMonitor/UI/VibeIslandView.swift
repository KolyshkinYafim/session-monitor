import AppKit
import SwiftUI

struct VibeIslandView: View {
    @Bindable var store: SessionStore
    @Bindable var ui: IslandUIState
    var commands: CommandBridge
    var bridgePath: String
    var onSizeChange: (CGSize) -> Void
    var onQuit: () -> Void

    private var currentSize: CGSize {
        switch ui.mode {
        // Heights match menu-bar strip so the pill sits in the top “curtain”.
        case .tucked: CGSize(width: 120, height: 22)
        case .pill: CGSize(width: store.waitingCount > 0 ? 188 : 152, height: 24)
        case .expanded: CGSize(width: 392, height: 400)
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

    // MARK: - Tucked (into Mac “curtain”)

    private var tuckedIsland: some View {
        Button {
            ui.mode = store.waitingCount > 0 || hasLive ? .pill : .expanded
        } label: {
            HStack(spacing: 6) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 36, height: 4)
                if store.waitingCount > 0 {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CurtainShell(topRadius: 0, bottomRadius: 10, waiting: store.waitingCount > 0))
        }
        .buttonStyle(.plain)
        .help("Session Monitor — click to show")
    }

    // MARK: - Pill

    private var pillIsland: some View {
        Button {
            ui.expand()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(leadingColor)

                HStack(spacing: -3) {
                    ForEach(collapsedDots.prefix(3)) { session in
                        Circle()
                            .fill(color(for: session.status))
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.8))
                    }
                }

                if store.waitingCount > 0 {
                    Text("\(store.waitingCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange))
                } else {
                    Text("\(liveCount)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Flat top (flush to screen edge), rounded bottom only.
            .background(CurtainShell(topRadius: 0, bottomRadius: 12, waiting: store.waitingCount > 0))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Expand") { ui.expand() }
            Button("Hide in menu bar") { ui.tuck() }
            Divider()
            Button("Quit") { onQuit() }
        }
        .help("Click to expand · ⌘⇧A · right-click to hide")
    }

    // MARK: - Expanded

    private var expandedIsland: some View {
        VStack(spacing: 0) {
            dragHandle
            header
            sessionList
            if let selected = selectedSession {
                detailPane(selected)
            }
            footer
        }
        .background(CurtainShell(topRadius: 0, bottomRadius: 22, waiting: store.waitingCount > 0))
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
                .fill(Color.white.opacity(0.2))
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
                if store.waitingCount > 0 {
                    Text("\(store.waitingCount) need your input")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text("Live agents")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            Spacer()
            Button {
                ui.tuck()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(6)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Hide into menu bar")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 5) {
                ForEach(store.islandSessions) { session in
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
        .frame(maxHeight: selectedSession?.status == .waitingInput ? 170 : 250)
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
                    Label("Open chat", systemImage: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.45, green: 0.82, blue: 1.0))
            }

            if session.status == .waitingInput {
                Text(session.pending?.promptText ?? "Agent is waiting for your input")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)

                if let options = session.pending?.options, !options.isEmpty {
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
                            .buttonStyle(IslandChipButton(accent: option.lowercased() == "deny"))
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("Reply to agent…", text: $ui.draftReply)
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
                            .background(Circle().fill(Color.white.opacity(0.92)))
                    }
                    .buttonStyle(.plain)
                    .disabled(ui.draftReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Text("Click Open chat to jump into Chat Hub · right-click row for more")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
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
            Text("⌘⇧A toggle · Esc collapse · ↑ hide")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
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

    private var selectedSession: SessionMeta? {
        guard let id = ui.selectedSessionId else {
            return store.islandSessions.first { $0.status == .waitingInput } ?? store.islandSessions.first
        }
        return store.sessions.first { $0.id == id } ?? store.islandSessions.first
    }

    private var collapsedDots: [SessionMeta] { store.islandSessions }

    private var liveCount: Int {
        store.sessions.filter(\.status.isLive).count
    }

    private var hasLive: Bool { liveCount > 0 }

    private var leadingSymbol: String {
        if store.waitingCount > 0 { return "exclamationmark.bubble.fill" }
        if hasLive { return "waveform" }
        return "circle.grid.2x1.fill"
    }

    private var leadingColor: Color {
        if store.waitingCount > 0 { return .orange }
        if hasLive { return Color(red: 0.4, green: 0.88, blue: 1.0) }
        return .white.opacity(0.7)
    }

    private func color(for status: SessionStatus) -> Color {
        switch status {
        case .running: Color(red: 0.2, green: 0.9, blue: 0.45)
        case .waitingInput: .orange
        case .error: Color(red: 1.0, green: 0.35, blue: 0.3)
        case .done: .white.opacity(0.3)
        case .idle: .white.opacity(0.22)
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
                        .fill(statusColor.opacity(0.16))
                        .frame(width: 26, height: 26)
                    Image(systemName: providerSymbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(session.provider.capitalized)
                            .foregroundStyle(Color(red: 0.45, green: 0.82, blue: 1.0))
                        Text("·").foregroundStyle(.white.opacity(0.22))
                        Text(shortPath(session.cwd))
                            .foregroundStyle(.white.opacity(0.38))
                            .lineLimit(1)
                    }
                    .font(.system(size: 10))
                }

                Spacer(minLength: 4)

                Text(session.status.label)
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(statusColor.opacity(0.14)))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected || session.status == .waitingInput
                          ? Color.white.opacity(0.09)
                          : Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        session.status == .waitingInput
                            ? Color.orange.opacity(0.45)
                            : Color.white.opacity(selected ? 0.12 : 0.04),
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

    private var statusColor: Color {
        switch session.status {
        case .running: Color(red: 0.2, green: 0.9, blue: 0.45)
        case .waitingInput: .orange
        case .error: Color(red: 1.0, green: 0.35, blue: 0.3)
        case .done: .white.opacity(0.4)
        case .idle: .white.opacity(0.32)
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
    var accent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(accent ? Color.red.opacity(0.9) : Color.white.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(accent ? Color.red.opacity(0.14) : Color.white.opacity(0.1))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Top edge flat (tucks into menu bar), bottom rounded like Dynamic Island growth.
private struct CurtainShell: View {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var waiting: Bool

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        )
        ZStack {
            shape.fill(Color.black.opacity(0.96))
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.03),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            shape.stroke(Color.white.opacity(waiting ? 0.18 : 0.1), lineWidth: 1)
            if waiting {
                shape.stroke(Color.orange.opacity(0.35), lineWidth: 1)
            }
        }
        // Soft drop only below — not a free-floating card in the middle of the desktop.
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        .shadow(color: waiting ? Color.orange.opacity(0.2) : .clear, radius: 10, y: 2)
    }
}

