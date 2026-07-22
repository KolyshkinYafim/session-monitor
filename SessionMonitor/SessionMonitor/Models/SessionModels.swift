import Foundation

enum SessionStatus: String, Codable, Sendable, CaseIterable {
    case idle
    case running
    case waitingInput = "waiting_input"
    case error
    case done
}

struct SessionMeta: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var title: String
    var provider: String
    var cwd: String?
    var status: SessionStatus
    var updatedAt: Date
    var createdAt: Date

    init(
        id: String,
        title: String,
        provider: String,
        cwd: String? = nil,
        status: SessionStatus,
        updatedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.provider = provider
        self.cwd = cwd
        self.status = status
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}

enum SessionEvent: Sendable {
    case upsert(SessionMeta)
    case status(id: String, status: SessionStatus)
    case ended(id: String, reason: EndReason)
    case permission(id: String, requestId: String, summary: String)
    case question(id: String, requestId: String, prompt: String, options: [String]?)
    case message(id: String, role: String, preview: String)

    enum EndReason: String, Sendable {
        case done
        case error
        case killed
    }
}

extension SessionStatus {
    var label: String {
        switch self {
        case .idle: "idle"
        case .running: "running"
        case .waitingInput: "waiting"
        case .error: "error"
        case .done: "done"
        }
    }
}
