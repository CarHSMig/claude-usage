import Foundation
import Testing
@testable import UsoClaudeCore

@Test func worktreeMapsToMainRepo() {
    #expect(projectName(forCwd: "/h/.herdr/worktrees/proteo-dev", gitCommonDir: "/h/dev/proteo/proteo/.git",
                        knownProjects: []) == "proteo")
}

@Test func deletedWorktreeUsesKnownPrefix() {
    #expect(projectName(forCwd: "/h/.herdr/worktrees/proteo-feat-5418-x", gitCommonDir: nil,
                        knownProjects: ["proteo"]) == "proteo")
}

@Test func plainFolderIsBasename() {
    #expect(projectName(forCwd: "/h/projetos/usage-tokens", gitCommonDir: nil, knownProjects: ["proteo"]) == "usage-tokens")
}

private func writeTranscript(in dir: URL, account: Account, session: String, lines: [String]) throws {
    let folder = URL(fileURLWithPath: account.directory).appendingPathComponent("projects/-x-pasta")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try lines.joined(separator: "\n").write(to: folder.appendingPathComponent("\(session).jsonl"), atomically: true, encoding: .utf8)
}

private let fixtureLines = [
    #"{"type":"user","timestamp":"2026-10-20T10:00:00.000Z","sessionId":"s1","cwd":"/x/pasta","message":{"content":"oi"}}"#,
    #"{"type":"system","subtype":"turn_duration","durationMs":60000,"timestamp":"2026-10-20T10:01:00.000Z","sessionId":"s1","cwd":"/x/pasta","isSidechain":false}"#,
    #"{"type":"system","subtype":"turn_duration","durationMs":30000,"timestamp":"2026-10-20T10:05:00.000Z","sessionId":"s1","cwd":"/x/pasta","isSidechain":true}"#,
    #"{"type":"ai-title","aiTitle":"Meu título","sessionId":"s1"}"#,
    #"{"type":"system","subtype":"turn_duration","durationMs":120000,"timestamp":"2026-10-25T12:00:00.000Z","sessionId":"s1","cwd":"/x/pasta","isSidechain":false}"#,
]

private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

@Test func importsTurnDurationsExactly() async throws {
    let dir = tempDir()
    let account = Account(label: "claude", directory: dir.appendingPathComponent("conta").path)
    try writeTranscript(in: dir, account: account, session: "s1", lines: fixtureLines)
    let db = try HoursDB(url: dir.appendingPathComponent("db.sqlite"))
    await HistoryImporter(db: db).importHistory(account: account, before: iso("2026-10-30T00:00:00Z"))
    let intervals = db.intervals(from: iso("2026-10-01T00:00:00Z"), to: iso("2026-11-01T00:00:00Z"), now: .now)
    #expect(intervals.count == 2)
    #expect(intervals[0].start == iso("2026-10-20T10:00:00Z") && intervals[0].end == iso("2026-10-20T10:01:00Z"))
    #expect(intervals[0].source == "import" && intervals[0].account == "claude")
    #expect(db.sessionTitles(["s1"]) == ["s1": "Meu título"])
}

@Test func importRespectsCutoff() async throws {
    let dir = tempDir()
    let account = Account(label: "claude", directory: dir.appendingPathComponent("conta").path)
    try writeTranscript(in: dir, account: account, session: "s1", lines: fixtureLines)
    let db = try HoursDB(url: dir.appendingPathComponent("db.sqlite"))
    await HistoryImporter(db: db).importHistory(account: account, before: iso("2026-10-22T00:00:00Z"))
    let intervals = db.intervals(from: iso("2026-10-01T00:00:00Z"), to: iso("2026-11-01T00:00:00Z"), now: .now)
    #expect(intervals.count == 1)
}

@Test func importRunsOnce() async throws {
    let dir = tempDir()
    let account = Account(label: "claude", directory: dir.appendingPathComponent("conta").path)
    try writeTranscript(in: dir, account: account, session: "s1", lines: fixtureLines)
    let db = try HoursDB(url: dir.appendingPathComponent("db.sqlite"))
    let importer = HistoryImporter(db: db)
    await importer.importHistory(account: account, before: iso("2026-10-22T00:00:00Z"))
    // Uma segunda importação, mesmo com corte maior, não acrescenta nada.
    await importer.importHistory(account: account, before: iso("2026-10-30T00:00:00Z"))
    #expect(db.intervals(from: iso("2026-10-01T00:00:00Z"), to: iso("2026-11-01T00:00:00Z"), now: .now).count == 1)
}

@Test func duplicatedTurnAcrossFilesCountsOnce() async throws {
    // Sessões retomadas/bifurcadas copiam o histórico para outro arquivo, com o mesmo uuid.
    let dir = tempDir()
    let account = Account(label: "claude", directory: dir.appendingPathComponent("conta").path)
    let line = #"{"type":"system","subtype":"turn_duration","durationMs":60000,"timestamp":"2026-10-20T10:01:00.000Z","sessionId":"SID","cwd":"/x/pasta","uuid":"u-1"}"#
    try writeTranscript(in: dir, account: account, session: "a", lines: [line.replacingOccurrences(of: "SID", with: "a")])
    try writeTranscript(in: dir, account: account, session: "b", lines: [line.replacingOccurrences(of: "SID", with: "b")])
    let db = try HoursDB(url: dir.appendingPathComponent("db.sqlite"))
    await HistoryImporter(db: db).importHistory(account: account, before: iso("2026-10-30T00:00:00Z"))
    #expect(db.intervals(from: iso("2026-10-01T00:00:00Z"), to: iso("2026-11-01T00:00:00Z"), now: .now).count == 1)
}

@Test func deletedClaudeWorktreeMapsToRepo() {
    #expect(projectName(forCwd: "/h/dev/proteo/proteo/.claude/worktrees/pr-5218-replication-lock", gitCommonDir: nil,
                        knownProjects: []) == "proteo")
}

@Test func deletedHerdrWorktreeMapsToRepo() {
    #expect(projectName(forCwd: "/h/.herdr/worktrees/proteo/feat-5732-x", gitCommonDir: nil, knownProjects: []) == "proteo")
}
