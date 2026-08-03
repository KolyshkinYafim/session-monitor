import Foundation

enum SessionStatus: String, Codable, Sendable, CaseIterable {
    case idle
    case running
    case waitingInput = "waiting_input"
    case error
    case done
}

/// Where the agent session lives.
enum SessionSource: String, Codable, Sendable, Equatable {
    case hub
    case terminal
    case mock
    case unknown
}

enum PendingInteraction: Sendable, Equatable {
    case permission(requestId: String, summary: String)
    case question(requestId: String, prompt: String, options: [String]?)
}

struct SessionMeta: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var title: String
    var provider: String
    /// Project folder name (basename of cwd) or explicit project label.
    var project: String?
    var cwd: String?
    /// Model id if known (e.g. claude-sonnet-4, gpt-5).
    var model: String?
    var status: SessionStatus
    var updatedAt: Date
    var createdAt: Date
    /// When the session was closed/ended (chat closed).
    var endedAt: Date?
    /// Last tool/activity line for the card subtitle.
    var lastActivity: String?
    var pending: PendingInteraction?
    var focusApp: String?
    var tty: String?
    var termSession: String?
    /// Terminal-specific handles for precise jumps (kitty window, wezterm pane, tmux pane…).
    var termIds: [String: String]?
    var source: SessionSource

    init(
        id: String,
        title: String,
        provider: String,
        project: String? = nil,
        cwd: String? = nil,
        model: String? = nil,
        status: SessionStatus,
        updatedAt: Date = Date(),
        createdAt: Date = Date(),
        endedAt: Date? = nil,
        lastActivity: String? = nil,
        pending: PendingInteraction? = nil,
        focusApp: String? = nil,
        tty: String? = nil,
        termSession: String? = nil,
        termIds: [String: String]? = nil,
        source: SessionSource = .unknown
    ) {
        self.id = id
        self.title = title
        self.provider = provider
        self.project = project ?? Self.projectName(from: cwd)
        self.cwd = cwd
        self.model = model
        self.status = status
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.endedAt = endedAt
        self.lastActivity = lastActivity
        self.pending = pending
        self.focusApp = focusApp
        self.tty = tty
        self.termSession = termSession
        self.termIds = termIds
        self.source = source == .unknown
            ? (focusApp != nil ? .terminal : (id.hasPrefix("mock-") ? .mock : .hub))
            : source
    }

    var isTerminalSession: Bool { source == .terminal || focusApp != nil }

    var isClosed: Bool {
        endedAt != nil || status == .done
    }

    var openActionLabel: String {
        if isMock { return "Demo only" }
        if isClosed { return "Reopen" }
        if isTerminalSession { return "Open terminal" }
        return "Open in Hub"
    }

    /// Short human status like Vibe: Ready / Running / Waiting / Done / Error
    var displayStatus: String {
        if isClosed { return "Closed" }
        switch status {
        case .idle: return "Ready"
        case .running: return "Running"
        case .waitingInput: return "Waiting"
        case .error: return "Error"
        case .done: return "Done"
        }
    }

    /// Terminal.app / iTerm / Chat Hub / etc.
    var hostLabel: String {
        if isMock { return "Demo" }
        if source == .hub { return "Chat Hub" }
        guard let app = focusApp?.lowercased() else { return "Terminal" }
        if app.contains("iterm") { return "iTerm" }
        if app.contains("ghostty") { return "Ghostty" }
        if app.contains("warp") { return "Warp" }
        if app.contains("kovidgoyal") || app.contains("kitty") { return "kitty" }
        if app.contains("wezterm") { return "WezTerm" }
        if app.contains("alacritty") { return "Alacritty" }
        if app.contains("zed") { return "Zed" }
        if app.contains("vscode") || app.contains("cursor") || app.contains("todesktop") { return "Editor" }
        if app.contains("terminal") { return "Terminal" }
        return "Terminal"
    }

    var providerLabel: String {
        provider.capitalized
    }

    /// A provider we never learned isn't worth a chip that says "Unknown".
    var showsProviderChip: Bool {
        let p = provider.lowercased()
        return !p.isEmpty && p != "unknown"
    }

    /// Older bridge rows carry the session uuid as their title. Showing a raw uuid on a
    /// card tells the user nothing, so fall back to the project.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !Self.looksLikeIdentifier(trimmed) else {
            return projectLabel == "—" ? "Session" : projectLabel
        }
        return trimmed
    }

    static func looksLikeIdentifier(_ text: String) -> Bool {
        if text == id_placeholder { return true }
        let body = text.hasPrefix("claude-") || text.hasPrefix("codex-")
            || text.hasPrefix("grok-") || text.hasPrefix("opencode-")
            ? String(text.drop(while: { $0 != "-" }).dropFirst())
            : text
        guard body.count >= 20 else { return false }
        let hexish = body.allSatisfy { $0.isHexDigit || $0 == "-" }
        return hexish && body.contains("-")
    }

    private static let id_placeholder = "unknown"

    var projectLabel: String {
        if let project, !project.isEmpty { return project }
        return Self.projectName(from: cwd) ?? "—"
    }

    static func projectName(from cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    enum CodingKeys: String, CodingKey {
        case id, title, provider, project, cwd, model, status
        case updatedAt, createdAt, endedAt, lastActivity
        case focusApp, tty, termSession, termIds, source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        provider = try c.decode(String.self, forKey: .provider)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        status = try c.decode(SessionStatus.self, forKey: .status)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? updatedAt
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        lastActivity = try c.decodeIfPresent(String.self, forKey: .lastActivity)
        focusApp = try c.decodeIfPresent(String.self, forKey: .focusApp)
        tty = try c.decodeIfPresent(String.self, forKey: .tty)
        termSession = try c.decodeIfPresent(String.self, forKey: .termSession)
        termIds = try c.decodeIfPresent([String: String].self, forKey: .termIds)
        source = try c.decodeIfPresent(SessionSource.self, forKey: .source) ?? .unknown
        if source == .unknown {
            source = focusApp != nil ? .terminal : (id.hasPrefix("mock-") ? .mock : .hub)
        }
        if project == nil {
            project = Self.projectName(from: cwd)
        }
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
        case .idle: "ready"
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

extension SessionMeta {
    var isMock: Bool { id.hasPrefix("mock-") || source == .mock }

    func relativeAge(from date: Date = Date()) -> String {
        let s = Int(date.timeIntervalSince(updatedAt))
        if s < 60 { return "<1m" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h" }
        return "\(s / 86_400)d"
    }
}
