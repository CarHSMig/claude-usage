import Foundation
import Testing
@testable import UsoClaudeCore

private func interval(_ project: String, account: String = "claude", session: String) -> StoredInterval {
    let now = Date()
    return StoredInterval(account: account, sessionId: session, project: project,
                          start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1800), source: "hook")
}

@Test func emptyFilterKeepsEverything() {
    let all = [interval("a", session: "1"), interval("b", account: "proteo", session: "2")]
    #expect(ReportFilter().applying(all).count == 2)
    #expect(ReportFilter().isEmpty)
}

@Test func filterByProjectsAndAccounts() {
    let all = [interval("a", session: "1"), interval("b", account: "proteo", session: "2"),
               interval("c", session: "3"), interval("a", account: "proteo", session: "4")]
    #expect(ReportFilter(projects: ["a", "b"]).applying(all).map(\.sessionId) == ["1", "2", "4"])
    #expect(ReportFilter(accounts: ["proteo"]).applying(all).map(\.sessionId) == ["2", "4"])
    #expect(ReportFilter(projects: ["a"], accounts: ["proteo"]).applying(all).map(\.sessionId) == ["4"])
}

@Test func toggling() {
    var filter = ReportFilter()
    filter.toggleProject("a")
    filter.toggleProject("b")
    filter.toggleProject("a")
    #expect(filter.projects == ["b"])
    filter.toggleAccount("claude")
    #expect(filter.accounts == ["claude"])
}

@MainActor @Test func storeFiltersReportButKeepsProjectListAndPersists() async throws {
    let dir = tempDir()
    let db = try HoursDB(url: dir.appendingPathComponent("db.sqlite"))
    let now = Date()
    db.replaceIntervals(session: "1", account: "claude", cwd: "/x/a",
                        [AIInterval(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-3000))], source: "hook")
    db.replaceIntervals(session: "2", account: "claude", cwd: "/x/b",
                        [AIInterval(start: now.addingTimeInterval(-2400), end: now.addingTimeInterval(-1200))], source: "hook")
    let defaults = UserDefaults(suiteName: "usoclaude-test-\(UUID().uuidString)")!
    let account = Account(label: "claude", directory: dir.path)
    let store = HoursStore(accounts: [account], db: db, eventsDir: dir, defaults: defaults)
    store.period = .custom(now.addingTimeInterval(-86_400), now)
    store.filter.toggleProject("b")
    await store.reload(now: now)
    #expect(abs((store.report?.total ?? 0) - 1200) < 0.01)
    #expect(store.listProjects.map(\.project) == ["b", "a"])

    let reopened = HoursStore(accounts: [account], db: db, eventsDir: dir, defaults: defaults)
    #expect(reopened.filter.projects == ["b"])
}
