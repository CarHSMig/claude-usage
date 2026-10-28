import Foundation
import Testing
@testable import UsoClaudeCore

private let binary = "/Applications/Uso Claude.app/Contents/MacOS/uso-claude-hook"

/// Mesmo formato do settings.json real do usuário (rtk + ai-memory).
private let realShape = #"""
{
  "model": "opus",
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "rtk hook claude"}]},
      {"matcher": "", "hooks": [{"type": "command", "command": "ai-memory hook --event pre-tool-use"}]}
    ],
    "Stop": [
      {"matcher": "", "hooks": [{"type": "command", "command": "ai-memory hook --event stop"}]}
    ]
  }
}
"""#

private func json(_ s: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any]
}

private func same(_ a: [String: Any], _ b: [String: Any]) -> Bool {
    NSDictionary(dictionary: a).isEqual(to: b)
}

private func commands(_ settings: [String: Any], event: String) -> [String] {
    let hooks = settings["hooks"] as? [String: Any]
    let entries = hooks?[event] as? [[String: Any]] ?? []
    return entries.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
}

@Test func addsOneEntryPerEventKeepingExisting() {
    let result = HooksInstaller.adding(to: json(realShape), account: "proteo", binary: binary)
    let ours = HooksInstaller.command(account: "proteo", binary: binary)
    #expect(commands(result, event: "PreToolUse") == ["rtk hook claude", "ai-memory hook --event pre-tool-use", ours])
    #expect(commands(result, event: "Stop") == ["ai-memory hook --event stop", ours])
    for event in HooksInstaller.hookEvents {
        #expect(commands(result, event: event).filter { $0 == ours }.count == 1)
    }
    #expect(result["model"] as? String == "opus")
    #expect(HooksInstaller.installed(in: result))
    #expect(!HooksInstaller.installed(in: json(realShape)))
}

@Test func installIsIdempotent() {
    let once = HooksInstaller.adding(to: json(realShape), account: "proteo", binary: binary)
    #expect(same(HooksInstaller.adding(to: once, account: "proteo", binary: binary), once))
}

@Test func createsHooksKeyWhenMissing() {
    let result = HooksInstaller.adding(to: ["model": "x"], account: "claude", binary: binary)
    #expect(result["model"] as? String == "x")
    #expect(HooksInstaller.hookEvents.allSatisfy { commands(result, event: $0).count == 1 })
}

@Test func removeOnlyOurs() {
    let original = json(realShape)
    #expect(same(HooksInstaller.removing(from: HooksInstaller.adding(to: original, account: "claude", binary: binary)), original))
}

@Test func installWritesBackupFirst() throws {
    let dir = tempDir()
    let settings = dir.appendingPathComponent("settings.json")
    try Data(realShape.utf8).write(to: settings)
    let now = Date(timeIntervalSince1970: 1_793_000_000)
    try HooksInstaller.install(settings: settings, account: "claude", binary: binary, now: now)
    let backup = dir.appendingPathComponent("settings.json.bak-usoclaude-1793000000")
    #expect(try Data(contentsOf: backup) == Data(realShape.utf8))
    let written = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    #expect(HooksInstaller.installed(in: written))
    try HooksInstaller.uninstall(settings: settings, now: now.addingTimeInterval(1))
    let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    #expect(same(restored, json(realShape)))
}

@Test func commandQuotesPathWithSpaces() {
    #expect(HooksInstaller.command(account: "proteo", binary: binary)
            == "'/Applications/Uso Claude.app/Contents/MacOS/uso-claude-hook' --account proteo")
}

@Test func invalidSettingsIsNotTouched() throws {
    let dir = tempDir()
    let settings = dir.appendingPathComponent("settings.json")
    try Data("{ inválido".utf8).write(to: settings)
    #expect(throws: (any Error).self) {
        try HooksInstaller.install(settings: settings, account: "claude", binary: binary, now: .now)
    }
    #expect(try Data(contentsOf: settings) == Data("{ inválido".utf8))
}
