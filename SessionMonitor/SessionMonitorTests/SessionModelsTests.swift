import XCTest

final class SessionModelsTests: XCTestCase {
    private func meta(
        id: String = "abc123",
        title: String = "Fix the parser",
        provider: String = "claude",
        project: String? = nil,
        cwd: String? = nil,
        status: SessionStatus = .running,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000_000),
        endedAt: Date? = nil,
        pending: PendingInteraction? = nil,
        focusApp: String? = nil,
        source: SessionSource = .unknown
    ) -> SessionMeta {
        SessionMeta(
            id: id,
            title: title,
            provider: provider,
            project: project,
            cwd: cwd,
            status: status,
            updatedAt: updatedAt,
            createdAt: updatedAt,
            endedAt: endedAt,
            pending: pending,
            focusApp: focusApp,
            source: source
        )
    }

    // MARK: - Project derivation

    func testProjectNameIsBasenameOfCwd() {
        XCTAssertEqual(SessionMeta.projectName(from: "/Users/me/dev/job-radar"), "job-radar")
        XCTAssertNil(SessionMeta.projectName(from: nil))
        XCTAssertNil(SessionMeta.projectName(from: ""))
    }

    func testInitDerivesProjectFromCwdWhenMissing() {
        XCTAssertEqual(meta(cwd: "/tmp/my-project").project, "my-project")
        XCTAssertEqual(meta(project: "explicit", cwd: "/tmp/other").project, "explicit")
    }

    // MARK: - Source inference

    func testUnknownSourceIsInferredFromShape() {
        XCTAssertEqual(meta(id: "mock-1").source, .mock)
        XCTAssertEqual(meta(focusApp: "iTerm").source, .terminal)
        XCTAssertEqual(meta().source, .hub)
    }

    func testExplicitSourceIsPreserved() {
        XCTAssertEqual(meta(focusApp: "iTerm", source: .hub).source, .hub)
    }

    // MARK: - Derived state

    func testIsClosedFromEndedAtOrDoneStatus() {
        XCTAssertFalse(meta().isClosed)
        XCTAssertTrue(meta(endedAt: Date()).isClosed)
        XCTAssertTrue(meta(status: .done).isClosed)
    }

    func testDisplayStatusClosedWinsOverLiveStatus() {
        XCTAssertEqual(meta(status: .running, endedAt: Date()).displayStatus, "Closed")
        XCTAssertEqual(meta(status: .running).displayStatus, "Running")
        XCTAssertEqual(meta(status: .waitingInput).displayStatus, "Waiting")
        XCTAssertEqual(meta(status: .idle).displayStatus, "Ready")
    }

    func testOpenActionLabelPerSessionKind() {
        XCTAssertEqual(meta(id: "mock-9").openActionLabel, "Demo only")
        XCTAssertEqual(meta(endedAt: Date()).openActionLabel, "Reopen")
        XCTAssertEqual(meta(focusApp: "iTerm").openActionLabel, "Open terminal")
        XCTAssertEqual(meta().openActionLabel, "Open in Hub")
    }

    func testHostLabelMapsBundleIdsToTerminalNames() {
        XCTAssertEqual(meta(id: "mock-1").hostLabel, "Demo")
        XCTAssertEqual(meta().hostLabel, "Chat Hub")
        XCTAssertEqual(meta(focusApp: "com.googlecode.iterm2").hostLabel, "iTerm")
        XCTAssertEqual(meta(focusApp: "com.mitchellh.ghostty").hostLabel, "Ghostty")
        XCTAssertEqual(meta(focusApp: "com.apple.Terminal").hostLabel, "Terminal")
        XCTAssertEqual(meta(focusApp: "something.else", source: .terminal).hostLabel, "Terminal")
    }

    func testShowsProviderChipHidesUnknownAndEmpty() {
        XCTAssertTrue(meta(provider: "claude").showsProviderChip)
        XCTAssertFalse(meta(provider: "unknown").showsProviderChip)
        XCTAssertFalse(meta(provider: "").showsProviderChip)
    }

    // MARK: - Identifier-shaped titles

    func testLooksLikeIdentifierDetectsUuidsAndPrefixedUuids() {
        XCTAssertTrue(SessionMeta.looksLikeIdentifier("0123abcd-4567-89ab-cdef-0123456789ab"))
        XCTAssertTrue(SessionMeta.looksLikeIdentifier("claude-0123abcd-4567-89ab-cdef-0123456789ab"))
        XCTAssertTrue(SessionMeta.looksLikeIdentifier("unknown"))
        XCTAssertFalse(SessionMeta.looksLikeIdentifier("Fix the parser"))
        XCTAssertFalse(SessionMeta.looksLikeIdentifier("abc-def"))
    }

    func testDisplayTitleFallsBackForIdentifierTitles() {
        let uuid = "0123abcd-4567-89ab-cdef-0123456789ab"
        XCTAssertEqual(meta(title: uuid, cwd: "/tmp/my-project").displayTitle, "my-project")
        XCTAssertEqual(meta(title: uuid).displayTitle, "Session")
        XCTAssertEqual(meta(title: "  Real title  ").displayTitle, "Real title")
    }

    // MARK: - Age formatting

    func testRelativeAgeBuckets() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let m = meta(updatedAt: base)
        XCTAssertEqual(m.relativeAge(from: base.addingTimeInterval(30)), "<1m")
        XCTAssertEqual(m.relativeAge(from: base.addingTimeInterval(120)), "2m")
        XCTAssertEqual(m.relativeAge(from: base.addingTimeInterval(7200)), "2h")
        XCTAssertEqual(m.relativeAge(from: base.addingTimeInterval(200_000)), "2d")
    }

    // MARK: - SessionStatus

    func testStatusIsLiveOnlyForActiveStates() {
        XCTAssertTrue(SessionStatus.running.isLive)
        XCTAssertTrue(SessionStatus.waitingInput.isLive)
        XCTAssertTrue(SessionStatus.error.isLive)
        XCTAssertFalse(SessionStatus.idle.isLive)
        XCTAssertFalse(SessionStatus.done.isLive)
    }

    func testStatusRawValuesMatchWireFormat() {
        XCTAssertEqual(SessionStatus.waitingInput.rawValue, "waiting_input")
        XCTAssertEqual(SessionStatus(rawValue: "waiting_input"), .waitingInput)
    }

    // MARK: - PendingInteraction

    func testPendingInteractionAccessors() {
        let permission = PendingInteraction.permission(requestId: "r1", summary: "Run rm -rf?")
        XCTAssertEqual(permission.requestId, "r1")
        XCTAssertEqual(permission.promptText, "Run rm -rf?")
        XCTAssertEqual(permission.options, ["Allow", "Deny"])

        let question = PendingInteraction.question(requestId: "r2", prompt: "Which branch?", options: ["main", "dev"])
        XCTAssertEqual(question.requestId, "r2")
        XCTAssertEqual(question.promptText, "Which branch?")
        XCTAssertEqual(question.options, ["main", "dev"])
    }

    // MARK: - Codable

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    func testCodableRoundTripPreservesFieldsAndDropsPending() throws {
        let original = meta(
            id: "s1",
            title: "Refactor collectors",
            project: "job-radar",
            cwd: "/Users/me/dev/job-radar",
            status: .waitingInput,
            pending: .permission(requestId: "req-1", summary: "Allow?"),
            focusApp: "com.googlecode.iterm2",
            source: .terminal
        )
        let decoded = try decoder.decode(SessionMeta.self, from: encoder.encode(original))

        // `pending` is runtime-only state — it is deliberately not part of CodingKeys.
        XCTAssertNil(decoded.pending)
        var expected = original
        expected.pending = nil
        XCTAssertEqual(decoded, expected)
    }

    func testDecodeMinimalPayloadAppliesFallbacks() throws {
        let json = Data("""
        {"id": "abc", "title": "Test", "provider": "claude", "status": "running"}
        """.utf8)
        let decoded = try decoder.decode(SessionMeta.self, from: json)
        XCTAssertEqual(decoded.status, .running)
        XCTAssertEqual(decoded.source, .hub)
        XCTAssertNil(decoded.project)
        XCTAssertEqual(decoded.createdAt, decoded.updatedAt)
    }

    func testDecodeInfersSourceAndProjectLikeInit() throws {
        let json = Data("""
        {"id": "abc", "title": "Test", "provider": "codex", "status": "waiting_input",
         "focusApp": "iTerm", "cwd": "/tmp/proj"}
        """.utf8)
        let decoded = try decoder.decode(SessionMeta.self, from: json)
        XCTAssertEqual(decoded.status, .waitingInput)
        XCTAssertEqual(decoded.source, .terminal)
        XCTAssertEqual(decoded.project, "proj")
    }
}
