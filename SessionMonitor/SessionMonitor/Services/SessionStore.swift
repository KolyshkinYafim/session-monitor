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
    /// Optional socket server for blocking PermissionRequest (terminal Claude hooks).
    weak var socketServer: MonitorSocketServer?
    /// Bumped on every status message so a late auto-clear can't wipe a newer one.
    private var openResultGeneration = 0
    /// True while the bridge feeds us history: those transitions already happened, and
    /// notifying/sounding them again means hundreds of banners at every launch.
    private(set) var isReplaying = false

    func setStatusChangeHandler(_ handler: @escaping (SessionMeta, SessionStatus, SessionStatus?) -> Void) {
        onStatusChange = handler
    }

    func beginReplay() {
        isReplaying = true
    }

    func endReplay() {
        isReplaying = false
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

    /// Hub / real sessions only (mock demos hidden when real data exists). Live-preferred:
    /// live sessions plus anything that finished its turn recently, so a session that just
    /// said "Done" doesn't vanish from the strip the moment another agent starts working.
    /// Used for the glanceable pill dots and as the expanded board's default (`.live`) filter.
    /// Genuinely empty when nothing is live or recent: a "last few we ever saw" fallback
    /// would pin a week-old board on screen and leave "hide when nothing is running" with
    /// no way to ever fire. History lives behind the `.all` filter.
    var islandSessions: [SessionMeta] {
        let cutoff = Date().addingTimeInterval(-Self.recentWindow)
        return islandSource.filter { $0.status.isLive || $0.updatedAt > cutoff }
    }

    /// A session that changed within this window still counts as "on screen".
    private static let recentWindow: TimeInterval = 10 * 60

    /// Sessions for the expanded board under an explicit status filter (`Live` / `All` /
    /// `Wait`) and origin (`Any` / `Hub` / `Term`).
    /// One shared cap: `All` rendering fewer rows than `Live` reads as a broken filter.
    func islandSessions(
        filter: IslandUIState.SessionFilter,
        source: IslandUIState.SourceFilter = .any
    ) -> [SessionMeta] {
        let rows: [SessionMeta]
        switch filter {
        case .live: rows = islandSessions
        case .all: rows = islandSource
        case .waiting: rows = islandSource.filter { $0.status == .waitingInput }
        }
        // Narrow before the cap: capping first would spend the 12 rows on the origin the
        // user just asked to hide.
        return Array(rows.filter { source.matches($0) }.prefix(Self.boardLimit))
    }

    private static let boardLimit = 12

    /// Real (non-local-demo) sessions when any exist, otherwise the demos — ordered.
    private var islandSource: [SessionMeta] {
        let real = orderedSessions.filter { !$0.isMock }
        return real.isEmpty ? orderedSessions : real
    }

    /// `at` is the event's own timestamp (the JSONL `ts`). Stamping wall-clock now instead
    /// would make every replayed line look like it just happened: the island would report
    /// a week of dead sessions as recent and the stale pruner could never fire.
    func apply(_ event: SessionEvent, at: Date = Date()) {
        switch event {
        case .upsert(let session):
            upsert(session)
        case .status(let id, let status):
            setStatus(id: id, status: status, clearPending: status != .waitingInput, at: at)
        case .ended(let id, let reason):
            let status: SessionStatus = reason == .error ? .error : .done
            markEnded(id: id, status: status, at: at)
        case .permission(let id, let requestId, let summary):
            setPending(id: id, pending: .permission(requestId: requestId, summary: summary), at: at)
        case .question(let id, let requestId, let prompt, let options):
            setPending(
                id: id,
                pending: .question(requestId: requestId, prompt: prompt, options: options),
                at: at
            )
        case .message(let id, let role, let preview):
            setActivity(id: id, role: role, preview: preview, at: at)
        }
    }

    /// Whether an answer from the island can actually reach the agent. A hook
    /// `session.question` on a terminal session has no reply channel at all: Chat Hub has
    /// never heard of a `claude-…` id, so offering Allow/Deny there is a lie.
    func canAnswer(_ session: SessionMeta) -> Bool {
        guard let pending = session.pending else { return false }
        switch pending {
        case .permission(let requestId, _):
            return socketServer?.isPending(requestId: requestId) == true || !session.isTerminalSession
        case .question:
            return !session.isTerminalSession
        }
    }

    func answer(sessionId: String, text: String, commands: CommandBridge) {
        guard var session = byId[sessionId] else { return }
        let requestId = session.pending?.requestId
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Only clear the card once the answer really left the building — an optimistic
        // "Running" over a still-blocked agent is worse than no button at all.
        var delivered = false

        // Blocking hook permission: Allow / Deny (or free-text "allow"/"deny").
        if case .permission = session.pending, let requestId {
            let allow = !(lower == "deny" || lower == "no" || lower == "reject")
            if socketServer?.resolve(requestId: requestId, allow: allow) == true {
                delivered = true
                setOpenResult(allow ? "Allowed in terminal agent" : "Denied in terminal agent")
            } else if session.isMock {
                delivered = true
                setOpenResult("Demo session — reply is local only")
            } else if session.isTerminalSession {
                setOpenResult("Permission timed out or Monitor missed the hook")
            } else {
                delivered = commands.reply(sessionId: sessionId, requestId: requestId, text: text)
                setOpenResult(
                    delivered
                        ? "Reply sent to Chat Hub"
                        : "Chat Hub not running — run: cd chat-hub && pnpm dev"
                )
            }
        } else if session.isMock {
            delivered = true
            setOpenResult("Demo session — reply is local only")
        } else if session.isTerminalSession {
            setOpenResult("Answer this in the terminal")
        } else {
            delivered = commands.reply(sessionId: sessionId, requestId: requestId, text: text)
            setOpenResult(
                delivered
                    ? "Reply sent to Chat Hub"
                    : "Chat Hub not running — run: cd chat-hub && pnpm dev"
            )
        }

        guard delivered else { return }
        session.pending = nil
        session.status = .running
        session.updatedAt = Date()
        byId[sessionId] = session
        publish()
    }

    func openChat(sessionId: String, commands: CommandBridge) {
        guard let session = byId[sessionId] else { return }
        if session.isMock {
            setOpenResult("Demo session (mock) — not in Chat Hub")
            return
        }
        // Terminal / hook sessions carry focusApp (bundle id of host terminal).
        if session.isTerminalSession, let app = session.focusApp {
            let ok = commands.focusTerminal(
                app: app,
                tty: session.tty,
                session: session.termSession,
                termIds: session.termIds,
                cwd: session.cwd
            )
            setOpenResult(
                ok
                    ? "Jumped to terminal"
                    : "Terminal not running — open \(app) and retry (allow Automation if asked)"
            )
            return
        }
        // Chat Hub sessions (no focusApp): focus via commands.jsonl + activate Hub.
        let ok = commands.focusSession(id: sessionId)
        setOpenResult(
            ok
                ? "Opened in Chat Hub"
                : "Chat Hub not running — run: cd chat-hub && pnpm dev"
        )
    }

    /// The hook holding this request went away (agent killed, terminal closed, timeout).
    /// Nobody can answer it any more, so stop showing it as something the user must decide.
    func cancelPending(sessionId: String, requestId: String) {
        guard var session = byId[sessionId],
              session.pending?.requestId == requestId
        else { return }
        let previous = session.status
        session.pending = nil
        session.status = .idle
        session.lastActivity = "Permission handled in terminal"
        session.updatedAt = Date()
        byId[sessionId] = session
        publish()
        if previous != .idle {
            emitStatusChange(session, .idle, previous)
        }
    }

    /// Sessions whose process died without a SessionEnd would otherwise stay "running"
    /// forever and keep the island lit. Called on a timer with `Preferences.idleCleanupHours`;
    /// 0 means the user turned cleanup off, so a long-lived session is never retired for them.
    func pruneStaleSessions(idleCleanupHours hours: Int) {
        guard hours > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        var changed = false
        for (id, session) in byId where session.status.isLive && session.updatedAt < cutoff {
            var next = session
            next.status = .done
            next.pending = nil
            next.endedAt = next.endedAt ?? session.updatedAt
            next.lastActivity = "Ended (no signal)"
            byId[id] = next
            changed = true
        }
        if changed { publish() }
    }

    func clearOpenResult() {
        openResultGeneration &+= 1
        lastOpenResult = nil
    }

    /// The line under the board is a toast, not state: a failure left pinned there for the
    /// rest of the session reads as "this is still broken" long after it was fixed.
    func setOpenResult(_ message: String) {
        openResultGeneration &+= 1
        let generation = openResultGeneration
        lastOpenResult = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.openResultLifetime))
            guard let self, self.openResultGeneration == generation else { return }
            self.lastOpenResult = nil
        }
    }

    private static let openResultLifetime: TimeInterval = 6

    func upsert(_ session: SessionMeta) {
        let previous = byId[session.id]
        var next = session
        if next.createdAt.timeIntervalSince1970 == 0 {
            next.createdAt = previous?.createdAt ?? Date()
        }
        // Merge sticky fields so partial updates don't wipe product metadata.
        if next.pending == nil { next.pending = previous?.pending }
        if next.focusApp == nil { next.focusApp = previous?.focusApp }
        if next.tty == nil { next.tty = previous?.tty }
        if next.termSession == nil { next.termSession = previous?.termSession }
        if next.termIds == nil { next.termIds = previous?.termIds }
        if next.model == nil { next.model = previous?.model }
        if next.project == nil { next.project = previous?.project }
        if next.lastActivity == nil { next.lastActivity = previous?.lastActivity }
        if next.endedAt == nil { next.endedAt = previous?.endedAt }
        if next.source == .unknown, let previous { next.source = previous.source }
        if next.status != .waitingInput {
            next.pending = nil
        }
        if next.status == .running || next.status == .waitingInput {
            next.endedAt = nil
        }
        byId[session.id] = next
        publish()
        if previous?.status != next.status {
            emitStatusChange(next, next.status, previous?.status)
        }
    }

    private func setStatus(id: String, status: SessionStatus, clearPending: Bool, at: Date) {
        guard var session = byId[id] else {
            upsert(
                SessionMeta(
                    id: id,
                    title: id,
                    provider: "unknown",
                    cwd: nil,
                    status: status,
                    updatedAt: at,
                    createdAt: at
                )
            )
            return
        }
        let previous = session.status
        if clearPending { session.pending = nil }
        if status == .done || status == .error {
            session.endedAt = session.endedAt ?? at
        } else if status == .running || status == .waitingInput {
            session.endedAt = nil
        }
        if previous == status {
            session.updatedAt = at
            byId[id] = session
            publish()
            return
        }
        session.status = status
        session.updatedAt = at
        byId[id] = session
        publish()
        emitStatusChange(session, status, previous)
    }

    private func markEnded(id: String, status: SessionStatus, at: Date) {
        guard var session = byId[id] else {
            setStatus(id: id, status: status, clearPending: true, at: at)
            return
        }
        let previous = session.status
        session.status = status
        session.pending = nil
        session.endedAt = at
        session.updatedAt = at
        session.lastActivity = status == .error ? "Session failed" : "Session closed"
        byId[id] = session
        publish()
        if previous != status {
            emitStatusChange(session, status, previous)
        }
    }

    private func setActivity(id: String, role: String, preview: String, at: Date) {
        guard var session = byId[id] else { return }
        let prefix = role == "tool" ? "⚙ " : (role == "assistant" ? "" : "\(role): ")
        session.lastActivity = prefix + preview
        session.updatedAt = at
        // A replayed message describes work that finished long ago; promoting the card
        // back to running would resurrect a session whose process is gone.
        if !isReplaying {
            if session.status == .idle { session.status = .running }
            session.endedAt = nil
        }
        byId[id] = session
        publish()
    }

    private func setPending(id: String, pending: PendingInteraction, at: Date) {
        var session = byId[id] ?? SessionMeta(
            id: id,
            title: id,
            provider: "unknown",
            status: .waitingInput,
            updatedAt: at,
            createdAt: at
        )
        // A blocking permission owns the card: Claude also emits a `permission_prompt`
        // notification for the same tool call, and letting that generic question replace
        // the permission would drop the Allow/Deny buttons and orphan the hook.
        if case .permission(let requestId, _) = session.pending,
           case .question = pending,
           socketServer?.isPending(requestId: requestId) == true {
            return
        }
        let previous = session.status
        session.pending = pending
        session.status = .waitingInput
        session.updatedAt = at
        byId[id] = session
        publish()
        if previous != .waitingInput {
            emitStatusChange(session, .waitingInput, previous)
        }
    }

    /// Replayed history must stay silent — otherwise every launch re-fires a banner and a
    /// sound for each of the hundreds of transitions already in the bridge file.
    private func emitStatusChange(
        _ session: SessionMeta,
        _ status: SessionStatus,
        _ previous: SessionStatus?
    ) {
        guard !isReplaying else { return }
        onStatusChange?(session, status, previous)
    }

    private func publish() {
        compactIfNeeded()
        sessions = Array(byId.values)
        waitingCount = sessions.filter { $0.status == .waitingInput && !$0.isMock }.count
    }

    /// Replaying a long bridge file resurrects every session that ever ran — hundreds of
    /// them after a busy week. Keep the recent ones and drop the oldest finished cards.
    private func compactIfNeeded() {
        guard byId.count > Self.maxSessions else { return }
        let finished = byId.values
            .filter { !$0.status.isLive }
            .sorted { $0.updatedAt < $1.updatedAt }
        let excess = byId.count - Self.maxSessions
        for session in finished.prefix(excess) {
            byId.removeValue(forKey: session.id)
        }
    }

    private static let maxSessions = 200
}
