import Foundation
import Testing
@testable import UsoClaudeCore

@Test func defaultDirUsesPlainService() {
    #expect(keychainService(for: "/Users/u/.claude", home: "/Users/u") == "Claude Code-credentials")
}

@Test func customDirUsesHashSuffix() {
    #expect(keychainService(for: "/Users/exemplo/.claude-proteo",
                            home: "/Users/exemplo") == "Claude Code-credentials-99f7bf74")
}

private func parse(_ json: String) throws -> [Account] {
    try AccountConfig.parse(Data(json.utf8), home: "/Users/u")
}

@Test func parsesLabelsAndExpandsHome() throws {
    let accounts = try parse(#"{"accounts":[{"label":"pessoal","directory":"~/.claude"},{"label":"trabalho","directory":"/opt/cc/"}]}"#)
    #expect(accounts == [Account(label: "pessoal", directory: "/Users/u/.claude"),
                         Account(label: "trabalho", directory: "/opt/cc")])
}

@Test func labelDefaultsToFolderNameWithoutLeadingDot() throws {
    let accounts = try parse(#"{"accounts":[{"directory":"~/.claude"},{"directory":"~/.claude work"}]}"#)
    #expect(accounts.map(\.label) == ["claude", "claude-work"])
}

@Test func rejectsBadConfigs() {
    #expect(throws: AccountConfigError.self) { try parse("não é json") }
    #expect(throws: AccountConfigError.self) { try parse(#"{"accounts":[]}"#) }
    #expect(throws: AccountConfigError.self) { try parse(#"{"accounts":[{"directory":"relativo/pasta"}]}"#) }
    #expect(throws: AccountConfigError.self) { try parse(#"{"accounts":[{"label":"a b","directory":"~/x"}]}"#) }
    #expect(throws: AccountConfigError.self) { try parse(#"{"accounts":[{"label":"a","directory":"~/x"},{"label":"a","directory":"~/y"}]}"#) }
    #expect(throws: AccountConfigError.self) { try parse(#"{"accounts":[{"label":"a","directory":"~/x"},{"label":"b","directory":"~/x/"}]}"#) }
}

@Test func missingFileIsCreatedWithTemplate() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = dir.appendingPathComponent("accounts.json")
    let loaded = AccountConfig.load(from: file, home: "/Users/u")
    #expect(loaded.accounts == [Account(label: "claude", directory: "/Users/u/.claude")])
    #expect(loaded.warning == nil)
    #expect(try String(contentsOf: file, encoding: .utf8) == AccountConfig.template)
}

@Test func invalidFileFallsBackWithWarning() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("accounts.json")
    try Data("{".utf8).write(to: file)
    let loaded = AccountConfig.load(from: file, home: "/Users/u")
    #expect(loaded.accounts.map(\.label) == ["claude"])
    #expect(loaded.warning?.contains(file.path) == true)
}
