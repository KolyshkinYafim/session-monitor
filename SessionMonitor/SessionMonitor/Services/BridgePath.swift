import Foundation

enum BridgePath {
    static var eventsFile: URL {
        if let override = ProcessInfo.processInfo.environment["AGENT_DESKTOP_EVENTS"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("agent-desktop", isDirectory: true)
            .appendingPathComponent("events.jsonl", isDirectory: false)
    }

    static var displayPath: String {
        eventsFile.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
