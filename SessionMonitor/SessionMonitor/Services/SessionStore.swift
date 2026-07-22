import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [SessionMeta] = []
    /// Waiting sessions that can open in Chat Hub (excludes mock-*).
    private(set) var waitingCount: Int = 0
    private(set) var lastOpenResult: String?

    private var byId: [String: SessionMeta] = [:]
    private var onStatusChange: ((SessionMeta, SessionStatus, SessionStatus?) -> Void)?

    func setStatusChangeHandler(_ handler: @escaping (SessionMeta, SessionStatus, SessionStatus?) -> Void) {
        onStatusChange = handler
    }

    var orderedSessions: [SessionMeta] {
        let priority: [SessionStatus] = [.waitingInput, .error, .running, .idle, .done]
        return sessions.sorted { a, b in
            let ia = priority.firstIndex(of: a.status) ?? 99
            let ib = priority.firstIndex(of: b.status) ?? 99
            if ia != ib { return ia < ib }
            return a.updatedAt > b.updatedAt
        }
    }

    /// Hub / real sessions only (mock demos hidden when real data exists).
    var islandSessions: [SessionMeta] {
        let real = orderedSessions.filter { !$0.isMock }
        let source = real.isEmpty ? orderedSessions : real
        let live = source.filter(\.status.isLive)
        if !live.isEmpty { return live }
        return Array(source.prefix(8))
    }

    func apply(_ event: SessionEvent) {
        switch event {
        case .upsert(let session):
            upsert(session)
        case .status(let id, let status):
            setStatus(id: id, status: status, clearPending: status != .waitingInput)
        case .ended(let id, let reason):
            let status: SessionStatus = reason == .error ? .error : .done
            setStatus(id: id, status: status, clearPending: true)
        case .permission(let id, let requestId, let summary):
            setPending(id: id, pending: .permission(requestId: requestId, summary: summary))
        case .question(let id, let requestId, let prompt, let options):
            setPending(
                id: id,
                pending: .question(requestId: requestId, prompt: prompt, options: options)
            )
        case .message(let id, _, _):
            touch(id: id)
        }
    }

    func answer(sessionId: String, text: String, commands: CommandBridge) {
        guard var session = byId[sessionId] else { return }
        let requestId = session.pending?.requestId
        if session.isMock {
            lastOpenResult = "Demo session — reply is local only"
        } else {
            commands.reply(sessionId: sessionId, requestId: requestId, text: text)
            lastOpenResult = "Reply sent to Chat Hub"
        }
        session.pending = nil
        session.status = .running
        session.updatedAt = Date()
        byId[sessionId] = session
        publish()
    }

    func openChat(sessionId: String, commands: CommandBridge) {
        guard let session = byId[sessionId] else { return }
        if session.isMock {
            lastOpenResult = "Demo session (mock) — not in Chat Hub"
            return
        }
        let ok = commands.focusSession(id: sessionId)
        lastOpenResult = ok
            ? "Opening in Chat Hub…"
            : "Chat Hub not running — start it (pnpm dev), then retry"
    }

    func clearOpenResult() {
        lastOpenResult = nil
    }

    func upsert(_ session: SessionMeta) {
        let previous = byId[session.id]
        var next = session
        if next.createdAt.timeIntervalSince1970 == 0 {
            next.createdAt = previous?.createdAt ?? Date()
        }
        if next.pending == nil {
            next.pending = previous?.pending
        }
        if next.status != .waitingInput {
            next.pending = nil
        }
        byId[session.id] = next
        publish()
        if previous?.status != next.status {
            onStatusChange?(next, next.status, previous?.status)
        }
    }

    private func setStatus(id: String, status: SessionStatus, clearPending: Bool) {
        guard var session = byId[id] else {
            upsert(
                SessionMeta(
                    id: id,
                    title: id,
                    provider: "unknown",
                    cwd: nil,
                    status: status
                )
            )
            return
        }
        let previous = session.status
        if clearPending { session.pending = nil }
        if previous == status {
            session.updatedAt = Date()
            byId[id] = session
            publish()
            return
        }
        session.status = status
        session.updatedAt = Date()
        byId[id] = session
        publish()
        onStatusChange?(session, status, previous)
    }

    private func setPending(id: String, pending: PendingInteraction) {
        var session = byId[id] ?? SessionMeta(
            id: id,
            title: id,
            provider: "unknown",
            status: .waitingInput
        )
        let previous = session.status
        session.pending = pending
        session.status = .waitingInput
        session.updatedAt = Date()
        byId[id] = session
        publish()
        if previous != .waitingInput {
            onStatusChange?(session, .waitingInput, previous)
        }
    }

    private func touch(id: String) {
        guard var session = byId[id] else { return }
        session.updatedAt = Date()
        byId[id] = session
        publish()
    }

    private func publish() {
        sessions = Array(byId.values)
        // Badge = real agents waiting for you (not demo mock cycle).
        waitingCount = sessions.filter { $0.status == .waitingInput && !$0.isMock }.count
    }
}

extension SessionMeta {
    var isMock: Bool {
        id.hasPrefix("mock-") || provider.lowercased() == "mock"
    }
}
