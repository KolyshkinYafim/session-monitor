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

    static var displayPath: String {
        eventsFile.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
