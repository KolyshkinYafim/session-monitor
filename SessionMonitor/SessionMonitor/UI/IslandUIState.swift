import Foundation
import Observation

@MainActor
@Observable
final class IslandUIState {
    enum Mode: Equatable {
        /// Collapsed DI strip under notch (dots + count). Default.
        case compact
        /// Hover / peek list under the strip.
        case activity
        /// Full board (⌘⇧A) with filters + reply.
        case expanded
    }

    enum SessionFilter: String, CaseIterable {
        case live = "Live"
        case all = "All"
        case waiting = "Wait"
    }

    /// Where the session came from. Chat Hub and the terminal hook both raise cards, and while
    /// you work in one of them the other is usually noise.
    enum SourceFilter: String, CaseIterable {
        case any = "Any"
        case hub = "Hub"
        case terminal = "Term"

        func matches(_ session: SessionMeta) -> Bool {
            switch self {
            case .any: true
            case .hub: session.source == .hub
            // The card's own notion of "terminal", so a row wearing a terminal chip can
            // never be the one this filter hides.
            case .terminal: session.isTerminalSession
            }
        }
    }

    var mode: Mode = .compact
    var selectedSessionId: String?
    var draftReply: String = ""
    var filter: SessionFilter = .live
    var sourceFilter: SourceFilter = .any
    var attentionPulse: Bool = false
    /// Published by the panel controller: NSScreen is not observable, so a view reading
    /// it in `body` never re-lays out when displays change.
    var metrics: IslandGeometry.Metrics?
    /// True while pointer is over the island (drives hover expand).
    var isHovering: Bool = false
    /// After ⌘⇧A expand, don't auto-collapse on mouse leave until user collapses.
    var pinExpanded: Bool = false
    /// The list was opened by an event (waiting / completion), not by the user. Such a
    /// reveal is a notification: it times out after `autoRevealDwell` instead of staying.
    var openedByEvent: Bool = false

    @ObservationIgnored private var pulseReset: Task<Void, Never>?

    var isExpanded: Bool { mode == .expanded }

    func expand(select id: String? = nil) {
        mode = .expanded
        pinExpanded = true
        openedByEvent = false
        if let id { selectedSessionId = id }
    }

    func collapseToActivity() {
        mode = .activity
        pinExpanded = false
        openedByEvent = false
        draftReply = ""
    }

    func compact() {
        mode = .compact
        pinExpanded = false
        openedByEvent = false
        draftReply = ""
        selectedSessionId = nil
    }

    func toggle() {
        if mode == .expanded {
            // Back to hover list if sessions, else compact
            mode = .activity
            pinExpanded = false
            openedByEvent = false
            draftReply = ""
        } else {
            expand()
        }
    }

    func triggerAttentionPulse() {
        attentionPulse = true
        // The glow is a cue, not a state: nothing else would ever turn it off.
        pulseReset?.cancel()
        pulseReset = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.attentionPulse = false
        }
    }

    /// Waiting forces a peek so the user sees the prompt without hunting.
    func presentForWaiting() {
        guard mode != .expanded else { return }
        mode = .activity
        openedByEvent = true
    }

    /// A finished turn gets the same timed peek. Only from compact: a list that is already
    /// open shows the result anyway, and re-flagging it as an event reveal would time out
    /// a board the user opened by hand.
    func presentForCompletion() {
        guard mode == .compact else { return }
        mode = .activity
        openedByEvent = true
    }
}
