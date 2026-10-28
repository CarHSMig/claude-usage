import CryptoKit
import Foundation

/// Uma conta do Claude Code, identificada pela pasta de configuração onde está logada.
public struct Account: Sendable, Identifiable, Hashable {
    public let label: String
    /// Caminho absoluto, com `~` já expandido.
    public let directory: String
    public var id: String { label }

    public init(label: String, directory: String) {
        self.label = label
        self.directory = directory
    }

    public static let all: [Account] = {
        let home = NSHomeDirectory()
        return [
            Account(label: "claude", directory: home + "/.claude"),
            Account(label: "proteo", directory: home + "/.claude-proteo"),
        ]
    }()

    public var keychainService: String {
        UsoClaudeCore.keychainService(for: directory, home: NSHomeDirectory())
    }
}

/// Nome do item no Keychain onde o Claude Code guarda o login de uma pasta.
/// A pasta padrão usa o nome sem sufixo; as demais recebem os 8 primeiros hex do SHA-256 do caminho.
public func keychainService(for directory: String, home: String) -> String {
    let base = "Claude Code-credentials"
    if directory == home + "/.claude" { return base }
    let digest = SHA256.hash(data: Data(directory.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return base + "-" + hex.prefix(8)
}
