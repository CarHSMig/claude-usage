import Testing
@testable import UsoClaudeCore

@Test func defaultDirUsesPlainService() {
    #expect(keychainService(for: "/Users/u/.claude", home: "/Users/u") == "Claude Code-credentials")
}

@Test func customDirUsesHashSuffix() {
    #expect(keychainService(for: "/Users/exemplo/.claude-proteo",
                            home: "/Users/exemplo") == "Claude Code-credentials-99f7bf74")
}

@Test func accountsAreTheTwoConfigured() {
    #expect(Account.all.map(\.label) == ["claude", "proteo"])
}
