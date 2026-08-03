import Foundation

enum BridgePath {
    static var agentDesktopDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("agent-desktop", isDirectory: true)
    }

    static var eventsFile: URL {
        if let override = ProcessInfo.processInfo.environment["AGENT_DESKTOP_EVENTS"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return agentDesktopDir.appendingPathComponent("events.jsonl", isDirectory: false)
    }

    /// Monitor → Hub reverse channel (focus chat, reply to waiting_input).
    static var commandsFile: URL {
        if let override = ProcessInfo.processInfo.environment["AGENT_DESKTOP_COMMANDS"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return agentDesktopDir.appendingPathComponent("commands.jsonl", isDirectory: false)
    }

    /// Bidirectional unix socket for blocking hooks (PermissionRequest).
    /// Override: `AGENT_DESKTOP_SOCKET`.
    static var socketFile: URL {
        if let override = ProcessInfo.processInfo.environment["AGENT_DESKTOP_SOCKET"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return agentDesktopDir.appendingPathComponent("monitor.sock", isDirectory: false)
    }

    static var displayPath: String {
        eventsFile.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    static var socketDisplayPath: String {
        socketFile.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
