import Foundation

public enum AccountState: Equatable, Sendable {
    case loading
    case ok(Usage, stale: Bool)
    case loginExpired
    /// Falhou sem ter números anteriores para mostrar (sem rede, erro do servidor ou resposta inesperada).
    case unavailable
}

private enum FetchOutcome: Sendable {
    case usage(Usage)
    case loginExpired
    case failed
}

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var states: [String: AccountState]
    /// Contas com uma busca em andamento, para a interface mostrar que o clique foi recebido.
    @Published public private(set) var refreshing: Set<String> = []

    public let accounts: [Account]
    private let source: UsageSource
    private var lastRefresh: Date?
    private var lastAccountRefresh: [String: Date] = [:]
    private(set) var timer: Timer?
    private var inFlight: Task<Void, Never>?

    private static let refreshInterval: TimeInterval = 150
    private static let clickDebounce: TimeInterval = 10
    private static let accountClickDebounce: TimeInterval = 5

    public init(accounts: [Account], source: UsageSource) {
        self.accounts = accounts
        self.source = source
        self.states = Dictionary(uniqueKeysWithValues: accounts.map { ($0.label, .loading) })
    }

    public var recommendedLabel: String? {
        // Números desatualizados só contam se nenhuma conta tiver números atuais.
        var fresh: [String: Usage] = [:]
        var stale: [String: Usage] = [:]
        for (label, state) in states {
            if case .ok(let usage, let isStale) = state {
                if isStale { stale[label] = usage } else { fresh[label] = usage }
            }
        }
        return recommended(fresh.isEmpty ? stale : fresh)
    }

    /// Se já houver uma atualização em andamento, espera por ela em vez de começar outra,
    /// para um resultado antigo nunca sobrescrever um mais novo.
    public func refresh() async {
        await run(accounts)
    }

    private func run(_ targets: [Account]) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await performRefresh(targets) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performRefresh(_ targets: [Account]) async {
        let now = Date()
        if targets.count == accounts.count { lastRefresh = now }
        for account in targets { lastAccountRefresh[account.label] = now }
        refreshing.formUnion(targets.map(\.label))
        defer { refreshing.subtract(targets.map(\.label)) }
        let source = self.source
        let outcomes = await withTaskGroup(of: (String, FetchOutcome).self) { group in
            for account in targets {
                group.addTask {
                    // O token é relido a cada ciclo para pegar renovações feitas pelo Claude Code.
                    guard let credential = await source.credential(for: account),
                          credential.expiresAt > Date() else {
                        return (account.label, .loginExpired)
                    }
                    do {
                        return (account.label, .usage(try await source.fetch(token: credential.accessToken)))
                    } catch UsageClientError.unauthorized {
                        return (account.label, .loginExpired)
                    } catch {
                        return (account.label, .failed)
                    }
                }
            }
            var result: [String: FetchOutcome] = [:]
            for await (label, outcome) in group { result[label] = outcome }
            return result
        }
        for (label, outcome) in outcomes {
            switch outcome {
            case .usage(let usage):
                states[label] = .ok(usage, stale: false)
            case .loginExpired:
                states[label] = .loginExpired
            case .failed:
                // Sem conexão: mantém os últimos números, marcados como desatualizados.
                if case .ok(let usage, _) = states[label] {
                    states[label] = .ok(usage, stale: true)
                } else {
                    states[label] = .unavailable
                }
            }
        }
    }

    /// Atualização disparada por clique; ignorada se houve outra há menos de 10 s.
    public func refreshIfIdle(now: Date = Date()) async {
        if let lastRefresh, now.timeIntervalSince(lastRefresh) < Self.clickDebounce { return }
        await refresh()
        lastRefresh = now
    }

    /// Atualização de uma conta só, disparada por clique no quadro dela; ignorada se essa conta
    /// foi atualizada há menos de 5 s (por clique ou pelo ciclo automático).
    public func refreshIfIdle(account label: String, now: Date = Date()) async {
        guard let account = accounts.first(where: { $0.label == label }) else { return }
        if let last = lastAccountRefresh[label], now.timeIntervalSince(last) < Self.accountClickDebounce { return }
        await run([account])
    }

    public func start() {
        Task { await refresh() }
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        // Modo comum: continua disparando com o menu aberto ou durante o arraste da janela.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
