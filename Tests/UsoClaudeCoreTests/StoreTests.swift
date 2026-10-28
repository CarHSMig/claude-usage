import Foundation
import Testing
@testable import UsoClaudeCore

private let a = Account(label: "a", directory: "/tmp/a")
private let b = Account(label: "b", directory: "/tmp/b")
private let sample = Usage(session: LimitWindow(utilization: 10, resetsAt: nil),
                           weekly: LimitWindow(utilization: 20, resetsAt: nil))

private actor FakeSource: UsageSource {
    var credentials: [String: Credential] = [:]
    var results: [String: [Result<Usage, Error>]] = [:]
    var fetchCount = 0

    init(credentials: [String: Credential], results: [String: [Result<Usage, Error>]]) {
        self.credentials = credentials
        self.results = results
    }

    func credential(for account: Account) async -> Credential? { credentials[account.label] }

    func fetch(token: String) async throws -> Usage {
        fetchCount += 1
        // O token do fake é o próprio rótulo da conta.
        let next = results[token]!.removeFirst()
        return try next.get()
    }
}

private func valid(_ label: String) -> Credential {
    Credential(accessToken: label, expiresAt: Date().addingTimeInterval(3600))
}

@MainActor @Test func expiredCredentialSkipsFetch() async {
    let source = FakeSource(credentials: ["a": Credential(accessToken: "a", expiresAt: Date().addingTimeInterval(-60))],
                            results: [:])
    let store = UsageStore(accounts: [a], source: source)
    await store.refresh()
    #expect(store.states["a"] == .loginExpired)
    #expect(await source.fetchCount == 0)
}

@MainActor @Test func missingCredentialIsLoginExpired() async {
    let source = FakeSource(credentials: ["b": valid("b")], results: ["b": [.success(sample)]])
    let store = UsageStore(accounts: [a, b], source: source)
    await store.refresh()
    #expect(store.states["a"] == .loginExpired)
    #expect(store.states["b"] == .ok(sample, stale: false))
}

@MainActor @Test func unauthorizedIsLoginExpired() async {
    let source = FakeSource(credentials: ["a": valid("a")], results: ["a": [.failure(UsageClientError.unauthorized)]])
    let store = UsageStore(accounts: [a], source: source)
    await store.refresh()
    #expect(store.states["a"] == .loginExpired)
}

@MainActor @Test func networkErrorKeepsLastValueAsStale() async {
    let source = FakeSource(credentials: ["a": valid("a")],
                            results: ["a": [.success(sample), .failure(URLError(.notConnectedToInternet))]])
    let store = UsageStore(accounts: [a], source: source)
    await store.refresh()
    await store.refresh()
    #expect(store.states["a"] == .ok(sample, stale: true))
}

@MainActor @Test func networkErrorWithoutPreviousValueIsUnavailable() async {
    let source = FakeSource(credentials: ["a": valid("a")], results: ["a": [.failure(URLError(.timedOut))]])
    let store = UsageStore(accounts: [a], source: source)
    await store.refresh()
    #expect(store.states["a"] == .unavailable)
}

@Test func liveSourceDoesNotCacheResponses() {
    #expect(LiveUsageSource.session.configuration.urlCache == nil)
}

@MainActor @Test func debounceSkipsWithin10s() async {
    let source = FakeSource(credentials: ["a": valid("a")], results: ["a": [.success(sample), .success(sample)]])
    let store = UsageStore(accounts: [a], source: source)
    let t = Date()
    await store.refreshIfIdle(now: t)
    await store.refreshIfIdle(now: t.addingTimeInterval(5))
    #expect(await source.fetchCount == 1)
}

@MainActor @Test func recommendedLabelUsesOkStates() async {
    let busy = Usage(session: LimitWindow(utilization: 0, resetsAt: nil), weekly: LimitWindow(utilization: 100, resetsAt: nil))
    let source = FakeSource(credentials: ["a": valid("a"), "b": valid("b")],
                            results: ["a": [.success(busy)], "b": [.success(sample)]])
    let store = UsageStore(accounts: [a, b], source: source)
    await store.refresh()
    #expect(store.recommendedLabel == "b")
}

@Test func parseCredentialReadsOauth() {
    let json = #"{"mcpOAuth":{},"claudeAiOauth":{"accessToken":"tok","refreshToken":"r","expiresAt":1800000000000}}"#
    let c = parseCredential(Data(json.utf8))
    #expect(c?.accessToken == "tok")
    #expect(c?.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
}

@Test func parseCredentialWithoutOauthKeyIsNil() {
    #expect(parseCredential(Data(#"{"mcpOAuth":{}}"#.utf8)) == nil)
}

@MainActor @Test func accountRefreshFetchesOnlyThatAccount() async {
    let source = FakeSource(credentials: ["a": valid("a"), "b": valid("b")],
                            results: ["a": [.success(sample)], "b": [.success(sample)]])
    let store = UsageStore(accounts: [a, b], source: source)
    await store.refreshIfIdle(account: "b")
    #expect(await source.fetchCount == 1)
    #expect(store.states["a"] == .loading)
    #expect(store.states["b"] == .ok(sample, stale: false))
    #expect(store.refreshing.isEmpty)
}

@MainActor @Test func accountRefreshDebouncesPerAccount() async {
    let source = FakeSource(credentials: ["a": valid("a"), "b": valid("b")],
                            results: ["a": [.success(sample), .success(sample)], "b": [.success(sample)]])
    let store = UsageStore(accounts: [a, b], source: source)
    let t = Date()
    await store.refreshIfIdle(account: "a", now: t)
    await store.refreshIfIdle(account: "a", now: t.addingTimeInterval(2))
    #expect(await source.fetchCount == 1)
    await store.refreshIfIdle(account: "b", now: t.addingTimeInterval(2))
    #expect(await source.fetchCount == 2)
    await store.refreshIfIdle(account: "a", now: t.addingTimeInterval(6))
    #expect(await source.fetchCount == 3)
}
