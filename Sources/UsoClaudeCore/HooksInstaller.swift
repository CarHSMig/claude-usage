import Foundation

/// Acrescenta ou remove os hooks do Uso Claude no `settings.json` de uma conta,
/// sem tocar nos hooks que já existem (rtk, ai-memory etc.).
public enum HooksInstaller {
    public static let hookEvents = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                                    "Notification", "PermissionRequest", "Stop", "SubagentStart",
                                    "SubagentStop", "SessionStart", "SessionEnd"]
    public static let defaultBinary = "/Applications/Uso Claude.app/Contents/MacOS/uso-claude-hook"
    private static let marker = "uso-claude-hook"

    public static func command(account: String, binary: String) -> String {
        "'\(binary)' --account \(account)"
    }

    private static func isOurs(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.contains(marker) ?? false
    }

    public static func installed(in json: [String: Any]) -> Bool {
        let hooks = json["hooks"] as? [String: Any] ?? [:]
        return hookEvents.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { entry in
                (entry["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs)
            }
        }
    }

    public static func adding(to json: [String: Any], account: String, binary: String) -> [String: Any] {
        var result = removing(from: json)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        let entry: [String: Any] = ["matcher": "", "hooks": [["type": "command", "command": command(account: account, binary: binary)]]]
        for event in hookEvents {
            hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [entry]
        }
        result["hooks"] = hooks
        return result
    }

    public static func removing(from json: [String: Any]) -> [String: Any] {
        var result = json
        guard var hooks = json["hooks"] as? [String: Any] else { return result }
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let cleaned: [[String: Any]] = entries.compactMap { entry in
                guard let inner = entry["hooks"] as? [[String: Any]] else { return entry }
                let kept = inner.filter { !isOurs($0) }
                if kept.count == inner.count { return entry }
                if kept.isEmpty { return nil }
                var copy = entry
                copy["hooks"] = kept
                return copy
            }
            hooks[event] = cleaned.isEmpty ? nil : cleaned
        }
        result["hooks"] = hooks.isEmpty ? nil : hooks
        return result
    }

    public static func install(settings: URL, account: String, binary: String = defaultBinary, now: Date) throws {
        try rewrite(settings: settings, now: now) { adding(to: $0, account: account, binary: binary) }
    }

    public static func uninstall(settings: URL, now: Date) throws {
        try rewrite(settings: settings, now: now) { removing(from: $0) }
    }

    /// Texto curto para o usuário revisar antes de confirmar.
    public static func previewDiff(settings: URL, account: String, binary: String = defaultBinary) -> String {
        """
        Arquivo: \(settings.path)
        Será feito um backup antes (settings.json.bak-usoclaude-…).
        Será acrescentado, em cada um destes eventos: \(hookEvents.joined(separator: ", "))
          {"matcher": "", "hooks": [{"type": "command", "command": "\(command(account: account, binary: binary))"}]}
        Os hooks que já existem não são alterados.
        """
    }

    private static func rewrite(settings: URL, now: Date, transform: ([String: Any]) -> [String: Any]) throws {
        let original = (try? Data(contentsOf: settings)) ?? Data("{}".utf8)
        // Se o arquivo não for um JSON válido, não mexe em nada.
        guard let json = try JSONSerialization.jsonObject(with: original) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let backup = settings.deletingLastPathComponent()
            .appendingPathComponent("settings.json.bak-usoclaude-\(Int(now.timeIntervalSince1970))")
        try original.write(to: backup)
        let data = try JSONSerialization.data(withJSONObject: transform(json),
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settings, options: .atomic)
    }
}
