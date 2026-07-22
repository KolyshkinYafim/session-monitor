import AppKit
import SwiftUI

struct VibeIslandView: View {
    @Bindable var store: SessionStore
    @Bindable var ui: IslandUIState
    var bridgePath: String
    var onSizeChange: (CGSize) -> Void
    var onQuit: () -> Void

    private let collapsedSize = CGSize(width: 168, height: 36)
    private let expandedSize = CGSize(width: 380, height: 360)

    var body: some View {
        ZStack(alignment: .top) {
            if ui.isExpanded {
                expandedIsland
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                        )
                    )
            } else {
                collapsedIsland
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .top))
                        )
                    )
            }
        }
        .frame(
            width: ui.isExpanded ? expandedSize.width : collapsedSize.width,
            height: ui.isExpanded ? expandedSize.height : collapsedSize.height,
            alignment: .top
        )
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: ui.isExpanded)
        .onAppear {
            emitSize()
        }
        .onChange(of: ui.isExpanded) { _, _ in
            emitSize()
        }
        .onExitCommand {
            if ui.isExpanded {
                ui.collapse()
            }
        }
    }

    private func emitSize() {
        onSizeChange(ui.isExpanded ? expandedSize : collapsedSize)
    }

    // MARK: - Collapsed (notch pill)

    private var collapsedIsland: some View {
        Button {
            ui.expand()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(leadingColor)
                    .symbolEffect(.pulse, isActive: store.waitingCount > 0 || hasRunning)

                HStack(spacing: -4) {
                    ForEach(collapsedDots.prefix(3)) { session in
                        Circle()
                            .fill(color(for: session.status))
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))
                    }
                }

                if store.waitingCount > 0 {
                    Text("\(store.waitingCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange))
                } else if !store.orderedSessions.isEmpty {
                    Text("\(liveCount)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(IslandShell(cornerRadius: 20, waiting: store.waitingCount > 0))
        }
        .buttonStyle(.plain)
        .help("Session Monitor — click to expand · ⌘⇧A")
    }

    // MARK: - Expanded

    private var expandedIsland: some View {
        VStack(spacing: 0) {
            expandedHeader
            if store.orderedSessions.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(store.orderedSessions) { session in
                            IslandSessionRow(
                                session: session,
                                highlighted: ui.highlightSessionId == session.id
                            ) {
                                ui.highlightSessionId = session.id
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
            expandedFooter
        }
        .background(IslandShell(cornerRadius: 26, waiting: store.waitingCount > 0))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var expandedHeader: some View {
        HStack(spacing: 10) {
            Button {
                ui.collapse()
            } label: {
                HStack(spacing: 8) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 28, height: 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 2)
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Sessions")
                    .font(.system(size: 12, weight: .semibold))
                if store.waitingCount > 0 {
                    Text("\(store.waitingCount) need input")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.leading, 14)
            .padding(.top, 18)
        }
        .overlay(alignment: .topTrailing) {
            Text("\(store.orderedSessions.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.trailing, 14)
                .padding(.top, 18)
        }
        .frame(height: 40)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
            Text("No live sessions")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text("Waiting for agents…")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var expandedFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 9, weight: .semibold))
            Text(bridgePath)
                .font(.system(size: 9, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Quit") { onQuit() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .foregroundStyle(.white.opacity(0.35))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var collapsedDots: [SessionMeta] {
        let priority: [SessionStatus] = [.waitingInput, .error, .running, .idle, .done]
        return store.orderedSessions.sorted { a, b in
            let ia = priority.firstIndex(of: a.status) ?? 99
            let ib = priority.firstIndex(of: b.status) ?? 99
            if ia != ib { return ia < ib }
            return a.updatedAt > b.updatedAt
        }
    }

    private var liveCount: Int {
        store.orderedSessions.filter { $0.status == .running || $0.status == .waitingInput }.count
    }

    private var hasRunning: Bool {
        store.orderedSessions.contains { $0.status == .running }
    }

    private var leadingSymbol: String {
        if store.waitingCount > 0 { return "exclamationmark.bubble.fill" }
        if hasRunning { return "ellipsis.bubble.fill" }
        return "circle.grid.2x2.fill"
    }

    private var leadingColor: Color {
        if store.waitingCount > 0 { return .orange }
        if hasRunning { return Color(red: 0.35, green: 0.85, blue: 1.0) }
        return .white.opacity(0.75)
    }

    private func color(for status: SessionStatus) -> Color {
        switch status {
        case .running: Color(red: 0.2, green: 0.9, blue: 0.45)
        case .waitingInput: .orange
        case .error: Color(red: 1.0, green: 0.35, blue: 0.3)
        case .done: .white.opacity(0.35)
        case .idle: .white.opacity(0.25)
        }
    }
}

struct IslandSessionRow: View {
    let session: SessionMeta
    var highlighted: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: providerSymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(session.provider.capitalized)
                            .foregroundStyle(Color(red: 0.45, green: 0.82, blue: 1.0))
                        Text("·").foregroundStyle(.white.opacity(0.25))
                        Text(shortPath(session.cwd))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                        Text("·").foregroundStyle(.white.opacity(0.25))
                        Text(relativeTime(session.updatedAt))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .font(.system(size: 10.5))
                }

                Spacer(minLength: 6)

                Text(session.status.label)
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.3)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(statusColor.opacity(0.14)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(highlighted || session.status == .waitingInput
                          ? Color.white.opacity(0.08)
                          : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        session.status == .waitingInput
                            ? Color.orange.opacity(0.4)
                            : Color.white.opacity(0.05),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy session ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            }
            if let cwd = session.cwd, !cwd.isEmpty {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
                }
            }
            Button("Open in Chat Hub (soon)") {}
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .running: Color(red: 0.2, green: 0.9, blue: 0.45)
        case .waitingInput: .orange
        case .error: Color(red: 1.0, green: 0.35, blue: 0.3)
        case .done: .white.opacity(0.45)
        case .idle: .white.opacity(0.35)
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

    private func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h"
    }
}

private struct IslandShell: View {
    var cornerRadius: CGFloat
    var waiting: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.94))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.02),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(waiting ? 0.14 : 0.06),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            if waiting {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1.2)
                    .blur(radius: 0.2)
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
        .shadow(color: waiting ? Color.orange.opacity(0.25) : .clear, radius: 14, y: 0)
    }
}
