import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [SessionMeta] = []
    private(set) var waitingCount: Int = 0

    private var byId: [String: SessionMeta] = [:]
    private var onStatusChange: ((SessionMeta, SessionStatus, SessionStatus?) -> Void)?

    func setStatusChangeHandler(_ handler: @escaping (SessionMeta, SessionStatus, SessionStatus?) -> Void) {
        onStatusChange = handler
    }

    var orderedSessions: [SessionMeta] {
        sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    func apply(_ event: SessionEvent) {
        switch event {
        case .upsert(let session):
            upsert(session)
        case .status(let id, let status):
            setStatus(id: id, status: status)
        case .ended(let id, let reason):
            let status: SessionStatus = reason == .error ? .error : .done
            setStatus(id: id, status: status)
        case .permission(let id, _, _):
            setStatus(id: id, status: .waitingInput)
        case .question(let id, _, _, _):
            setStatus(id: id, status: .waitingInput)
        case .message(let id, _, _):
            touch(id: id)
        }
    }

    func upsert(_ session: SessionMeta) {
        let previous = byId[session.id]
        var next = session
        if next.createdAt.timeIntervalSince1970 == 0 {
            next.createdAt = previous?.createdAt ?? Date()
        }
        byId[session.id] = next
        publish()
        if previous?.status != next.status {
            onStatusChange?(next, next.status, previous?.status)
        }
    }

    private func setStatus(id: String, status: SessionStatus) {
        guard var session = byId[id] else {
            let skeleton = SessionMeta(
                id: id,
                title: id,
                provider: "unknown",
                cwd: nil,
                status: status
            )
            upsert(skeleton)
            return
        }
        let previous = session.status
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

    private func touch(id: String) {
        guard var session = byId[id] else { return }
        session.updatedAt = Date()
        byId[id] = session
        publish()
    }

    private func publish() {
        sessions = Array(byId.values)
        waitingCount = sessions.filter { $0.status == .waitingInput }.count
    }
}
