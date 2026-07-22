import Foundation

enum SessionStatus: String, Codable, Sendable, CaseIterable {
    case idle
    case running
    case waitingInput = "waiting_input"
    case error
    case done
}

enum PendingInteraction: Sendable, Equatable {
    case permission(requestId: String, summary: String)
    case question(requestId: String, prompt: String, options: [String]?)
}

struct SessionMeta: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var title: String
    var provider: String
    var cwd: String?
    var status: SessionStatus
    var updatedAt: Date
    var createdAt: Date
    var pending: PendingInteraction?
    /// App to bring forward when this session is opened (bundle id or name). Set by terminal
    /// hook sessions to the host terminal; `nil` means route through Chat Hub (default).
    var focusApp: String?

    init(
        id: String,
        title: String,
        provider: String,
        cwd: String? = nil,
        status: SessionStatus,
        updatedAt: Date = Date(),
        createdAt: Date = Date(),
        pending: PendingInteraction? = nil,
        focusApp: String? = nil
    ) {
        self.id = id
        self.title = title
        self.provider = provider
        self.cwd = cwd
        self.status = status
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.pending = pending
        self.focusApp = focusApp
    }

    /// Sessions that live in a terminal (via the Claude Code hook) rather than in Chat Hub.
    var isTerminalSession: Bool { focusApp != nil }

    /// Label for the primary "open" action in the island detail pane.
    var openActionLabel: String {
        if isMock { return "Demo only" }
        if isTerminalSession { return "Open terminal" }
        return "Open in Hub"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, provider, cwd, status, updatedAt, createdAt, focusApp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        provider = try c.decode(String.self, forKey: .provider)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        status = try c.decode(SessionStatus.self, forKey: .status)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? updatedAt
        focusApp = try c.decodeIfPresent(String.self, forKey: .focusApp)
        pending = nil
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

    var isLive: Bool {
        self == .running || self == .waitingInput || self == .error
    }
}

extension PendingInteraction {
    var promptText: String {
        switch self {
        case .permission(_, let summary): summary
        case .question(_, let prompt, _): prompt
        }
    }

    var requestId: String {
        switch self {
        case .permission(let id, _): id
        case .question(let id, _, _): id
        }
    }

    var options: [String]? {
        switch self {
        case .permission: ["Allow", "Deny"]
        case .question(_, _, let options): options
        }
    }
}
