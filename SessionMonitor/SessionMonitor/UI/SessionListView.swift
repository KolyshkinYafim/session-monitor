import AppKit
import SwiftUI

struct SessionListView: View {
    @Bindable var store: SessionStore
    var bridgePath: String
    var onHide: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            if store.orderedSessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.orderedSessions) { session in
                            SessionRowView(session: session)
                        }
                    }
                    .padding(10)
                }
            }
            Divider().overlay(Color.white.opacity(0.08))
            footer
        }
        .frame(width: 360, height: 420)
        .background(IslandBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(1)
        .onExitCommand(perform: onHide)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Session Monitor")
                    .font(.system(size: 13, weight: .semibold))
                Text("Agent sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(store.waitingCount)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(store.waitingCount > 0 ? Color.black : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(store.waitingCount > 0 ? Color.orange : Color.white.opacity(0.08))
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("No sessions")
                .font(.system(size: 13, weight: .medium))
            Text("Mock + Chat Hub bridge will appear here")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bridge")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(bridgePath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Quit") { onQuit() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct SessionRowView: View {
    let session: SessionMeta

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(session.status.label.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.14), in: Capsule())
                }

                HStack(spacing: 4) {
                    Text(session.provider)
                        .foregroundStyle(Color.cyan.opacity(0.9))
                    Text("·").foregroundStyle(.tertiary)
                    Text(shortPath(session.cwd))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("·").foregroundStyle(.tertiary)
                    Text(relativeTime(session.updatedAt))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(session.status == .waitingInput ? Color.orange.opacity(0.35) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .contentShape(Rectangle())
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
            Button("Activate (stub)") {}
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .running: .green
        case .waitingInput: .orange
        case .error: .red
        case .done: .secondary
        case .idle: Color.gray.opacity(0.7)
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
        let hours = minutes / 60
        return "\(hours)h"
    }
}

private struct IslandBackground: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.09, green: 0.10, blue: 0.13).opacity(0.92),
                            Color(red: 0.06, green: 0.07, blue: 0.09).opacity(0.96)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}
