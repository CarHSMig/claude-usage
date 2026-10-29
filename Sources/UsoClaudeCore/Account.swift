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

    /// Contas lidas de `accounts.json` (veja `AccountConfig`) quando o app abre.
    public static let loaded = AccountConfig.load()
    public static var all: [Account] { loaded.accounts }

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

/// Erro de leitura do `accounts.json`, com mensagem pronta para mostrar ao usuário.
public struct AccountConfigError: Error, LocalizedError, Equatable {
    public let message: String
    public var errorDescription: String? { message }
}

/// As contas ficam num arquivo do usuário, `~/Library/Application Support/UsoClaude/accounts.json`:
///
///     { "accounts": [ { "label": "pessoal", "directory": "~/.claude" },
///                     { "directory": "~/.claude-trabalho" } ] }
///
/// `directory` é a pasta de configuração de uma conta do Claude Code (aceita `~`). `label` é opcional: sem ele, vale o
/// nome da pasta sem o ponto inicial. O nome aparece na janela e identifica a conta nos dados de horas.
public enum AccountConfig {
    public static var file: URL { DataPaths.root.appendingPathComponent("accounts.json") }

    /// Criado na primeira abertura: só a pasta padrão do Claude Code.
    public static let template = """
    {
      "accounts": [
        { "label": "claude", "directory": "~/.claude" }
      ]
    }
    """

    public struct Loaded: Sendable {
        public let accounts: [Account]
        /// Preenchido quando o arquivo existe mas não pôde ser usado; as contas são então só a padrão.
        public let warning: String?
    }

    private struct FileContents: Decodable {
        var accounts: [Entry]
    }

    private struct Entry: Decodable {
        var label: String?
        var directory: String
    }

    public static func parse(_ data: Data, home: String) throws -> [Account] {
        let contents: FileContents
        do {
            contents = try JSONDecoder().decode(FileContents.self, from: data)
        } catch {
            throw AccountConfigError(message: "o arquivo não está no formato esperado: "
                + "{ \"accounts\": [ { \"label\": \"nome\", \"directory\": \"~/.claude\" } ] }")
        }
        guard !contents.accounts.isEmpty else {
            throw AccountConfigError(message: "a lista \"accounts\" está vazia")
        }
        var accounts: [Account] = []
        for entry in contents.accounts {
            let directory = try normalized(entry.directory, home: home)
            let label = try entry.label.map { try validated($0.trimmingCharacters(in: .whitespaces)) }
                ?? derivedLabel(directory)
            if let clash = accounts.first(where: { $0.label == label || $0.directory == directory }) {
                throw AccountConfigError(message: clash.label == label
                    ? "o nome \"\(label)\" aparece em mais de uma conta"
                    : "a pasta \(directory) aparece em mais de uma conta")
            }
            accounts.append(Account(label: label, directory: directory))
        }
        return accounts
    }

    /// Lê o arquivo. Se não existe, cria com o modelo. Se está inválido, usa só a conta padrão e devolve o motivo.
    public static func load(from url: URL = file, home: String = NSHomeDirectory(),
                            fileManager: FileManager = .default) -> Loaded {
        let fallback = (try? parse(Data(template.utf8), home: home)) ?? []
        guard fileManager.fileExists(atPath: url.path) else {
            try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(template.utf8).write(to: url)
            return Loaded(accounts: fallback, warning: nil)
        }
        do {
            return Loaded(accounts: try parse(try Data(contentsOf: url), home: home), warning: nil)
        } catch {
            let reason = (error as? AccountConfigError)?.message ?? error.localizedDescription
            return Loaded(accounts: fallback,
                          warning: "Não foi possível usar \(url.path): \(reason).\nPor enquanto o app usa só ~/.claude.")
        }
    }

    private static func normalized(_ raw: String, home: String) throws -> String {
        var path = raw.trimmingCharacters(in: .whitespaces)
        if path == "~" { path = home } else if path.hasPrefix("~/") { path = home + path.dropFirst(1) }
        guard path.hasPrefix("/") else {
            throw AccountConfigError(message: "a pasta \"\(raw)\" precisa ser um caminho completo (ou começar com ~/)")
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// O nome vai para a linha de comando do hook e para nomes de arquivo, então fica restrito a caracteres seguros.
    private static func validated(_ label: String) throws -> String {
        guard !label.isEmpty, label.allSatisfy({ isSafe($0) }) else {
            throw AccountConfigError(message: "o nome \"\(label)\" é inválido: use só letras, números, ponto, hífen e sublinhado")
        }
        return label
    }

    private static func derivedLabel(_ directory: String) -> String {
        let name = String(URL(fileURLWithPath: directory).lastPathComponent.drop(while: { $0 == "." }))
        let label = String(name.map { isSafe($0) ? $0 : "-" })
        return label.isEmpty ? "conta" : label
    }

    private static func isSafe(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "." || c == "-" || c == "_")
    }
}
