import Foundation
import Testing
@testable import UsoClaudeCore

@MainActor @Test func reloadProducesReportFromIngestedEvents() async throws {
    let dir = tempDir()
    let db = try HoursDB(url: dir.appendingPathComponent("db.sqlite"))
    let account = Account(label: "claude", directory: dir.appendingPathComponent("conta").path)
    let now = Date()
    let start = now.addingTimeInterval(-600)
    var data = Data()
    for (name, ts) in [("UserPromptSubmit", start), ("Stop", start.addingTimeInterval(300))] {
        data.append(encodeEventLine(HookEvent(ts: ts, event: name, sessionId: "s", cwd: "/x/pasta",
                                              transcriptPath: nil, toolName: nil, notificationType: nil)))
    }
    try data.write(to: dir.appendingPathComponent("claude.jsonl"))
    let store = HoursStore(accounts: [account], db: db, eventsDir: dir)
    store.period = .custom(now.addingTimeInterval(-86_400), now)
    await store.reload(now: now)
    #expect(abs((store.report?.total ?? 0) - 300) < 0.01, "total = \(String(describing: store.report?.total))")
}

@Test func forcedReimportExtendsCutoffWithoutDuplicates() async throws {
    let dir = tempDir()
    let account = Account(label: "claude", directory: dir.appendingPathComponent("conta").path)
    let folder = URL(fileURLWithPath: account.directory).appendingPathComponent("projects/-x")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let lines = [
        #"{"type":"system","subtype":"turn_duration","durationMs":60000,"timestamp":"2026-10-20T10:01:00.000Z","sessionId":"s","cwd":"/x","uuid":"a"}"#,
        #"{"type":"system","subtype":"turn_duration","durationMs":60000,"timestamp":"2026-10-25T10:01:00.000Z","sessionId":"s","cwd":"/x","uuid":"b"}"#,
    ]
    try lines.joined(separator: "\n").write(to: folder.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
    let db = try HoursDB(url: dir.appendingPathComponent("db.sqlite"))
    let importer = HistoryImporter(db: db)
    let iso = ISO8601DateFormatter()
    await importer.importHistory(account: account, before: iso.date(from: "2026-10-22T00:00:00Z")!)
    // Ao ativar os hooks, reimporta até o momento da ativação.
    await importer.importHistory(account: account, before: iso.date(from: "2026-10-30T00:00:00Z")!, force: true)
    await importer.importHistory(account: account, before: iso.date(from: "2026-10-30T00:00:00Z")!, force: true)
    #expect(db.intervals(from: .distantPast, to: .distantFuture, now: .now).count == 2)
}

@Test func reimportSkipsTurnsAlreadyCoveredByHooks() async throws {
    let dir = tempDir()
    let account = Account(label: "claude", directory: dir.appendingPathComponent("conta").path)
    let folder = URL(fileURLWithPath: account.directory).appendingPathComponent("projects/-x")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let lines = [
        #"{"type":"system","subtype":"turn_duration","durationMs":60000,"timestamp":"2026-10-20T10:01:00.000Z","sessionId":"s","cwd":"/x","uuid":"a"}"#,
        #"{"type":"system","subtype":"turn_duration","durationMs":60000,"timestamp":"2026-10-25T10:01:00.000Z","sessionId":"s","cwd":"/x","uuid":"b"}"#,
    ]
    try lines.joined(separator: "\n").write(to: folder.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
    let db = try HoursDB(url: dir.appendingPathComponent("db.sqlite"))
    let iso = ISO8601DateFormatter()
    // Os hooks registraram a sessão "s" a partir de 22/10: o turno de 25/10 já está nos hooks.
    db.insertEvents([HookEvent(ts: iso.date(from: "2026-10-22T09:00:00Z")!, event: "UserPromptSubmit", sessionId: "s",
                               cwd: "/x", transcriptPath: nil, toolName: nil, notificationType: nil)], account: "claude")
    await HistoryImporter(db: db).importHistory(account: account, before: iso.date(from: "2026-10-30T00:00:00Z")!, force: true)
    let imported = db.intervals(from: .distantPast, to: .distantFuture, now: .now).filter { $0.source == "import" }
    #expect(imported.count == 1)
    #expect(imported.first?.end == iso.date(from: "2026-10-20T10:01:00Z"))
}

@MainActor @Test func concurrentReloadsDoNotDuplicateEvents() async throws {
    let dir = tempDir()
    let db = try HoursDB(url: dir.appendingPathComponent("db.sqlite"))
    var data = Data()
    let now = Date()
    for i in 0..<200 {
        data.append(encodeEventLine(HookEvent(ts: now.addingTimeInterval(Double(-400 + i)), event: "PostToolUse", sessionId: "s",
                                              cwd: "/x", transcriptPath: nil, toolName: nil, notificationType: nil)))
    }
    try data.write(to: dir.appendingPathComponent("claude.jsonl"))
    let store = HoursStore(accounts: [Account(label: "claude", directory: dir.path)], db: db, eventsDir: dir,
                           defaults: UserDefaults(suiteName: "usoclaude-test-\(UUID().uuidString)")!)
    async let first: Void = store.reload(now: now)
    async let second: Void = store.reload(now: now)
    async let third: Void = store.reload(now: now)
    _ = await (first, second, third)
    #expect(db.events(session: "s").count == 200)
}
