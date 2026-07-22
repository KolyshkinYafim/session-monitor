import Foundation
import Observation

@MainActor
@Observable
final class IslandUIState {
    enum Mode: Equatable {
        /// Fully tucked into the menu-bar / notch “curtain”.
        case tucked
        /// Compact live pill under the curtain.
        case pill
        /// Expanded session board.
        case expanded
    }

    var mode: Mode = .pill
    var selectedSessionId: String?
    var draftReply: String = ""

    var isExpanded: Bool { mode == .expanded }

    func toggle() {
        mode = mode == .expanded ? .pill : .expanded
        if mode != .expanded {
            draftReply = ""
        }
    }

    func expand(select id: String? = nil) {
        mode = .expanded
        if let id { selectedSessionId = id }
    }

    func collapseToPill() {
        mode = .pill
        draftReply = ""
    }

    func tuck() {
        mode = .tucked
        draftReply = ""
        selectedSessionId = nil
    }
}
