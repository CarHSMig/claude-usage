import Foundation

public enum UsageClientError: Error {
    case unauthorized
    case badStatus(Int)
}

/// De onde vêm o login e os números de uso; trocado por um fake nos testes.
public protocol UsageSource: Sendable {
    func credential(for account: Account) async -> Credential?
    func fetch(token: String) async throws -> Usage
}

public struct LiveUsageSource: UsageSource {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Sessão sem cache em disco, para o request (com o token no header) nunca ser gravado.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    public init() {}

    public func credential(for account: Account) async -> Credential? {
        await readKeychainCredential(service: account.keychainService)
    }

    public func fetch(token: String) async throws -> Usage {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw UsageClientError.unauthorized }
        guard status == 200 else { throw UsageClientError.badStatus(status) }
        return try parseUsage(data)
    }
}
