import Foundation

public struct Credential: Sendable {
    public let accessToken: String
    public let expiresAt: Date

    public init(accessToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }
}

private struct RawCredential: Decodable {
    struct OAuth: Decodable {
        let accessToken: String
        let expiresAt: Double
    }
    let claudeAiOauth: OAuth
}

/// Lê o JSON que o Claude Code guarda no Keychain. `expiresAt` vem em milissegundos.
public func parseCredential(_ data: Data) -> Credential? {
    guard let raw = try? JSONDecoder().decode(RawCredential.self, from: data) else { return nil }
    return Credential(accessToken: raw.claudeAiOauth.accessToken,
                      expiresAt: Date(timeIntervalSince1970: raw.claudeAiOauth.expiresAt / 1000))
}

/// Lê o login do Keychain pelo binário `security`, que já tem acesso aos itens do Claude Code
/// sem disparar pedido de permissão. Só leitura: nunca grava nem renova o token.
func readKeychainCredential(service: String) async -> Credential? {
    guard let data = await runProcess("/usr/bin/security", ["find-generic-password", "-s", service, "-w"],
                                      timeout: 5) else { return nil }
    return parseCredential(data)
}

/// Roda um processo fora do pool cooperativo e devolve o stdout, ou `nil` se falhar
/// ou passar do tempo limite (o processo é encerrado).
func runProcess(_ path: String, _ arguments: [String], timeout: TimeInterval) async -> Data? {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            continuation.resume(returning: runProcessBlocking(path, arguments, timeout: timeout))
        }
    }
}

private func runProcessBlocking(_ path: String, _ arguments: [String], timeout: TimeInterval) -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }
    do {
        try process.run()
    } catch {
        return nil
    }
    // A saída esperada é pequena (cabe no buffer do pipe), então dá para ler só depois que o processo sai.
    guard exited.wait(timeout: .now() + timeout) == .success else {
        process.terminate()
        return nil
    }
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else { return nil }
    return data
}
