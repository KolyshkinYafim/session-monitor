import XCTest

/// Mode transitions of the island UI state machine: compact ↔ activity ↔ expanded,
/// plus the event-driven reveals and their guards.
@MainActor
final class IslandUIStateTests: XCTestCase {
    func testInitialState() {
        let state = IslandUIState()
        XCTAssertEqual(state.mode, .compact)
        XCTAssertEqual(state.filter, .live)
        XCTAssertEqual(state.sourceFilter, .any)
        XCTAssertFalse(state.pinExpanded)
        XCTAssertFalse(state.openedByEvent)
        XCTAssertNil(state.selectedSessionId)
    }

    func testExpandPinsAndSelectsSession() {
        let state = IslandUIState()
        state.expand(select: "abc")
        XCTAssertEqual(state.mode, .expanded)
        XCTAssertTrue(state.pinExpanded)
        XCTAssertFalse(state.openedByEvent)
        XCTAssertEqual(state.selectedSessionId, "abc")
    }

    func testExpandWithoutIdKeepsSelection() {
        let state = IslandUIState()
        state.selectedSessionId = "keep-me"
        state.expand()
        XCTAssertEqual(state.selectedSessionId, "keep-me")
    }

    func testCollapseToActivityClearsPinAndDraft() {
        let state = IslandUIState()
        state.expand()
        state.draftReply = "half-typed reply"
        state.collapseToActivity()
        XCTAssertEqual(state.mode, .activity)
        XCTAssertFalse(state.pinExpanded)
        XCTAssertEqual(state.draftReply, "")
    }

    func testCompactResetsSelectionAndDraft() {
        let state = IslandUIState()
        state.expand(select: "abc")
        state.draftReply = "draft"
        state.compact()
        XCTAssertEqual(state.mode, .compact)
        XCTAssertNil(state.selectedSessionId)
        XCTAssertEqual(state.draftReply, "")
        XCTAssertFalse(state.pinExpanded)
    }

    func testToggleFromCompactExpands() {
        let state = IslandUIState()
        state.toggle()
        XCTAssertEqual(state.mode, .expanded)
        XCTAssertTrue(state.pinExpanded)
    }

    func testToggleFromExpandedDropsToActivity() {
        let state = IslandUIState()
        state.expand()
        state.draftReply = "draft"
        state.toggle()
        XCTAssertEqual(state.mode, .activity)
        XCTAssertFalse(state.pinExpanded)
        XCTAssertEqual(state.draftReply, "")
    }

    func testPresentForWaitingOpensActivityAsEventReveal() {
        let state = IslandUIState()
        state.presentForWaiting()
        XCTAssertEqual(state.mode, .activity)
        XCTAssertTrue(state.openedByEvent)
    }

    func testPresentForWaitingNeverDemotesExpandedBoard() {
        let state = IslandUIState()
        state.expand()
        state.presentForWaiting()
        XCTAssertEqual(state.mode, .expanded)
        XCTAssertFalse(state.openedByEvent)
    }

    func testPresentForCompletionOnlyFiresFromCompact() {
        let state = IslandUIState()
        state.presentForCompletion()
        XCTAssertEqual(state.mode, .activity)
        XCTAssertTrue(state.openedByEvent)
    }

    func testPresentForCompletionDoesNotReflagOpenList() {
        // A list the user opened by hand must not become a timed event reveal.
        let state = IslandUIState()
        state.collapseToActivity()
        state.presentForCompletion()
        XCTAssertEqual(state.mode, .activity)
        XCTAssertFalse(state.openedByEvent)
    }

    // MARK: - SourceFilter

    private func session(id: String, source: SessionSource, focusApp: String? = nil) -> SessionMeta {
        SessionMeta(id: id, title: "t", provider: "claude", status: .running, focusApp: focusApp, source: source)
    }

    func testSourceFilterAnyMatchesEverything() {
        XCTAssertTrue(IslandUIState.SourceFilter.any.matches(session(id: "1", source: .hub)))
        XCTAssertTrue(IslandUIState.SourceFilter.any.matches(session(id: "2", source: .terminal)))
    }

    func testSourceFilterHubMatchesOnlyHubSessions() {
        XCTAssertTrue(IslandUIState.SourceFilter.hub.matches(session(id: "1", source: .hub)))
        XCTAssertFalse(IslandUIState.SourceFilter.hub.matches(session(id: "2", source: .terminal)))
    }

    func testSourceFilterTerminalUsesCardNotionOfTerminal() {
        // A hub-sourced session with a focusApp still wears a terminal chip → must match.
        XCTAssertTrue(IslandUIState.SourceFilter.terminal.matches(session(id: "1", source: .terminal)))
        XCTAssertTrue(IslandUIState.SourceFilter.terminal.matches(session(id: "2", source: .hub, focusApp: "iTerm")))
        XCTAssertFalse(IslandUIState.SourceFilter.terminal.matches(session(id: "3", source: .hub)))
    }
}
