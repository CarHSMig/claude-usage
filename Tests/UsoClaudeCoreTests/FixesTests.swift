import CoreFoundation
import Foundation
import Testing
@testable import UsoClaudeCore

private let a = Account(label: "a", directory: "/tmp/a")
private let b = Account(label: "b", directory: "/tmp/b")

private func usage(weekly: Double) -> Usage {
    Usage(session: LimitWindow(utilization: 10, resetsAt: nil), weekly: LimitWindow(utilization: weekly, resetsAt: nil))
}

private func valid(_ label: String) -> Credential {
    Credential(accessToken: label, expiresAt: Date().addingTimeInterval(3600))
}

/// Fonte fake que demora para responder e devolve resultados em sequência por conta.
private actor SlowSource: UsageSource {
    var results: [String: [Result<Usage, Error>]]
    let delay: Duration
    var fetchCount = 0

    init(results: [String: [Result<Usage, Error>]], delay: Duration = .zero) {
        self.results = results
        self.delay = delay
    }

    func credential(for account: Account) async -> Credential? { valid(account.label) }

    func fetch(token: String) async throws -> Usage {
        fetchCount += 1
        let next = results[token]!.removeFirst()
        try? await Task.sleep(for: delay)
        return try next.get()
    }
}

@Test func processTimeoutReturnsNil() async {
    let start = Date()
    let data = await runProcess("/bin/sleep", ["10"], timeout: 0.5)
    #expect(data == nil)
    #expect(Date().timeIntervalSince(start) < 3)
}

@Test func processOutputIsReturned() async {
    let data = await runProcess("/bin/echo", ["oi"], timeout: 5)
    #expect(data.map { String(decoding: $0, as: UTF8.self) } == "oi\n")
}

@Test func processFailureReturnsNil() async {
    #expect(await runProcess("/usr/bin/false", [], timeout: 5) == nil)
}

@MainActor @Test func overlappingRefreshesFetchOnce() async {
    let source = SlowSource(results: ["a": [.success(usage(weekly: 1)), .success(usage(weekly: 2))]],
                            delay: .milliseconds(200))
    let store = UsageStore(accounts: [a], source: source)
    async let first: Void = store.refresh()
    async let second: Void = store.refresh()
    _ = await (first, second)
    #expect(await source.fetchCount == 1)
    #expect(store.states["a"] == .ok(usage(weekly: 1), stale: false))
}

@MainActor @Test func staleDataIsNotRecommended() async {
    let source = SlowSource(results: ["a": [.success(usage(weekly: 10)), .failure(URLError(.timedOut))],
                                      "b": [.success(usage(weekly: 50)), .success(usage(weekly: 50))]])
    let store = UsageStore(accounts: [a, b], source: source)
    await store.refresh()
    #expect(store.recommendedLabel == "a")
    await store.refresh()
    #expect(store.states["a"] == .ok(usage(weekly: 10), stale: true))
    #expect(store.recommendedLabel == "b")
}

@MainActor @Test func allStaleStillRecommends() async {
    let source = SlowSource(results: ["a": [.success(usage(weekly: 10)), .failure(URLError(.timedOut))],
                                      "b": [.success(usage(weekly: 50)), .failure(URLError(.timedOut))]])
    let store = UsageStore(accounts: [a, b], source: source)
    await store.refresh()
    await store.refresh()
    #expect(store.recommendedLabel == "a")
}

@MainActor @Test func timerRunsInCommonModes() async {
    let source = SlowSource(results: ["a": [.success(usage(weekly: 1))]])
    let store = UsageStore(accounts: [a], source: source)
    store.start()
    defer { store.timer?.invalidate() }
    let timer = try! #require(store.timer)
    #expect(CFRunLoopContainsTimer(CFRunLoopGetMain(), timer, .commonModes))
}
