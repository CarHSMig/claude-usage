import Foundation
import Testing
@testable import UsoClaudeCore

func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("usoclaude-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let base = Date(timeIntervalSince1970: 1_793_000_000)
private func t(_ minute: Double) -> Date { base.addingTimeInterval(minute * 60) }
private func ev(_ name: String, _ minute: Double, session: String = "s1") -> HookEvent {
    HookEvent(ts: t(minute), event: name, sessionId: session, cwd: "/x/pasta", transcriptPath: nil,
              toolName: nil, notificationType: nil)
}

private func append(_ events: [HookEvent], to url: URL, trailingPartial: String? = nil) {
    var data = Data()
    for e in events { data.append(encodeEventLine(e)) }
    if let trailingPartial { data.append(Data(trailingPartial.utf8)) }
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try! data.write(to: url)
    }
}

@Test func ingestBuildsIntervalsAndAdvancesOffset() throws {
    let dir = tempDir()
    let db = try HoursDB(url: dir.appendingPathComponent("db.sqlite"))
    let ingestor = EventIngestor(db: db, eventsDir: dir)
    append([ev("UserPromptSubmit", 0), ev("PostToolUse", 2), ev("Stop", 5)], to: dir.appendingPathComponent("claude.jsonl"))
    #expect(ingestor.ingest(account: "claude", now: t(60)) == ["s1"])
    let intervals = db.intervals(from: t(-60), to: t(120), now: t(60))
    #expect(intervals == [StoredInterval(account: "claude", sessionId: "s1", project: "pasta",
                                         start: t(0), end: t(5), source: "hook")])
    #expect(ingestor.ingest(account: "claude", now: t(60)).isEmpty)
}

@Test func partialTrailingLineWaitsForNewline() throws {
    let dir = tempDir()
    let db = try HoursDB(url: dir.appendingPathComponent("db.sqlite"))
    let ingestor = EventIngestor(db: db, eventsDir: dir)
    let file = dir.appendingPathComponent("claude.jsonl")
    let stop = String(decoding: encodeEventLine(ev("Stop", 5)), as: UTF8.self)
    append([ev("UserPromptSubmit", 0)], to: file, trailingPartial: String(stop.prefix(10)))
    _ = ingestor.ingest(account: "claude", now: t(6))
    #expect(db.intervals(from: t(-60), to: t(120), now: t(6)).first?.end == nil)
    append([], to: file, trailingPartial: String(stop.dropFirst(10)))
    _ = ingestor.ingest(account: "claude", now: t(6))
    #expect(db.intervals(from: t(-60), to: t(120), now: t(6)).first?.end == t(5))
}

@Test func incrementalIngestRebuildsSessionAcrossReads() throws {
    let dir = tempDir()
    let db = try HoursDB(url: dir.appendingPathComponent("db.sqlite"))
    let ingestor = EventIngestor(db: db, eventsDir: dir)
    let file = dir.appendingPathComponent("claude.jsonl")
    append([ev("UserPromptSubmit", 0)], to: file)
    _ = ingestor.ingest(account: "claude", now: t(1))
    append([ev("Stop", 5)], to: file)
    _ = ingestor.ingest(account: "claude", now: t(6))
    let intervals = db.intervals(from: t(-60), to: t(120), now: t(6))
    #expect(intervals.count == 1 && intervals[0].start == t(0) && intervals[0].end == t(5))
}

@Test func intervalsQueryReturnsOverlapping() throws {
    let db = try HoursDB(url: tempDir().appendingPathComponent("db.sqlite"))
    db.replaceIntervals(session: "s", account: "claude", cwd: "/x/pasta",
                        [AIInterval(start: t(0), end: t(30))], source: "hook")
    #expect(db.intervals(from: t(20), to: t(100), now: t(200)).count == 1)
    #expect(db.intervals(from: t(31), to: t(100), now: t(200)).isEmpty)
}

@Test func projectFallbackIsCwdBasename() throws {
    let db = try HoursDB(url: tempDir().appendingPathComponent("db.sqlite"))
    db.replaceIntervals(session: "s", account: "claude", cwd: "/x/pasta",
                        [AIInterval(start: t(0), end: t(30))], source: "hook")
    #expect(db.intervals(from: t(0), to: t(30), now: t(30)).first?.project == "pasta")
    db.setProject("proteo", forCwd: "/x/pasta")
    #expect(db.intervals(from: t(0), to: t(30), now: t(30)).first?.project == "proteo")
}

@Test func replacedEventsFileIsReadFromStart() throws {
    let dir = tempDir()
    let db = try HoursDB(url: dir.appendingPathComponent("db.sqlite"))
    let ingestor = EventIngestor(db: db, eventsDir: dir)
    let file = dir.appendingPathComponent("claude.jsonl")
    append([ev("UserPromptSubmit", 0), ev("PostToolUse", 1), ev("PostToolUse", 2), ev("Stop", 3)], to: file)
    ingestor.ingest(account: "claude", now: t(60))
    // O arquivo é apagado e recriado (menor que o ponto já lido).
    try FileManager.default.removeItem(at: file)
    append([ev("UserPromptSubmit", 10, session: "s2"), ev("Stop", 12, session: "s2")], to: file)
    #expect(ingestor.ingest(account: "claude", now: t(60)) == ["s2"])
}

@Test func rebuildAllRecomputesEverySession() throws {
    let dir = tempDir()
    let db = try HoursDB(url: dir.appendingPathComponent("db.sqlite"))
    db.insertEvents([ev("UserPromptSubmit", 0, session: "a"), ev("Stop", 5, session: "a"),
                     ev("UserPromptSubmit", 0, session: "b"), ev("Stop", 2, session: "b")], account: "claude")
    EventIngestor(db: db, eventsDir: dir).rebuildAll(account: "claude", now: t(60))
    #expect(Set(db.intervals(from: t(-1), to: t(10), now: t(60)).map(\.sessionId)) == ["a", "b"])
}
