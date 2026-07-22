import Foundation

@MainActor
final class MockProducer {
    private let store: SessionStore
    private var timer: Timer?
    private var phases: [String: Int] = [:]

    private let cycle: [SessionStatus] = [.running, .waitingInput, .running, .done]
    private let seeds: [(id: String, title: String, provider: String, cwd: String, offset: Int)] = [
        ("mock-grok-1", "Refactor auth middleware", "grok", "/Users/dev/projects/api", 0),
        ("mock-claude-1", "Fix flaky e2e suite", "claude", "/Users/dev/projects/web", 1),
        ("mock-codex-1", "Add session metrics", "codex", "/Users/dev/projects/monitor", 2)
    ]

    init(store: SessionStore) {
        self.store = store
    }

    func start() {
        let now = Date()
        for seed in seeds {
            let phase = seed.offset % cycle.count
            phases[seed.id] = phase
            let created = now.addingTimeInterval(TimeInterval(-seed.offset * 60))
            store.apply(
                .upsert(
                    SessionMeta(
                        id: seed.id,
                        title: seed.title,
                        provider: seed.provider,
                        cwd: seed.cwd,
                        status: cycle[phase],
                        updatedAt: now,
                        createdAt: created
                    )
                )
            )
        }

        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        for seed in seeds {
            let next = ((phases[seed.id] ?? 0) + 1) % cycle.count
            phases[seed.id] = next
            let status = cycle[next]
            switch status {
            case .waitingInput:
                store.apply(
                    .question(
                        id: seed.id,
                        requestId: "q-\(seed.id)-\(Int(Date().timeIntervalSince1970))",
                        prompt: "Continue with destructive change?",
                        options: ["Allow", "Deny"]
                    )
                )
            case .done:
                store.apply(.status(id: seed.id, status: .done))
                store.apply(.ended(id: seed.id, reason: .done))
            default:
                store.apply(.status(id: seed.id, status: status))
            }
        }
    }
}
