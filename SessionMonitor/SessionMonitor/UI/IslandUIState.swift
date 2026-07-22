import Foundation
import Observation

@MainActor
@Observable
final class IslandUIState {
    var isExpanded = false
    var highlightSessionId: String?

    func toggle() {
        isExpanded.toggle()
    }

    func expand() {
        isExpanded = true
    }

    func collapse() {
        isExpanded = false
        highlightSessionId = nil
    }
}
