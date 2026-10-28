import Foundation

/// Junta tudo das horas de IA para a interface: importação inicial, leitura dos eventos dos hooks,
/// relatório do período escolhido e ativação/desativação dos hooks.
@MainActor
public final class HoursStore: ObservableObject {
    public enum PeriodKind: String, CaseIterable, Sendable { case day, week, month, custom }

    @Published public var period: ReportPeriod {
        didSet { Task { await reload() } }
    }
    @Published public private(set) var report: HoursReport?
    @Published public private(set) var importing = false
    @Published public private(set) var hooksActive: [String: Bool] = [:]
    @Published public private(set) var sessionTitles: [String: String] = [:]
    /// Filtro por projeto/conta; vale para o total, o gráfico e o tooltip, e é lembrado entre execuções.
    @Published public var filter: ReportFilter {
        didSet {
            if let data = try? JSONEncoder().encode(filter) { defaults.set(data, forKey: Self.filterKey) }
            Task { await reload() }
        }
    }
    /// Projetos do período ignorando o filtro de projeto (para o menu e a lista, com os de fora apagados).
    @Published public private(set) var listProjects: [ProjectRow] = []

    public let accounts: [Account]
    private let db: HoursDB
    private let eventsDir: URL
    private var timer: Timer?
    private var lastTitleScan: Date?
    private var reloadTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private static let filterKey = "hoursFilter"

    private static let ingestInterval: TimeInterval = 10
    private static let titleScanInterval: TimeInterval = 300

    public var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    public init(accounts: [Account], db: HoursDB, eventsDir: URL, defaults: UserDefaults = .standard) {
        self.accounts = accounts
        self.db = db
        self.eventsDir = eventsDir
        self.defaults = defaults
        self.period = .day(Date())
        self.filter = defaults.data(forKey: Self.filterKey)
            .flatMap { try? JSONDecoder().decode(ReportFilter.self, from: $0) } ?? ReportFilter()
        refreshHooksActive()
    }

    public func start() {
        Task {
            let pending = accounts.filter { db.ingestState(account: $0.label).historyImportedAt == nil }
            if !pending.isEmpty {
                importing = true
                let importer = HistoryImporter(db: db)
                for account in pending {
                    let cutoff = db.ingestState(account: account.label).hooksInstalledAt ?? Date()
                    await Task.detached { await importer.importHistory(account: account, before: cutoff) }.value
                }
                importing = false
            }
            // Recalcula as sessões já gravadas, caso as regras de contagem tenham mudado desde a última execução.
            let (db, eventsDir, labels) = (self.db, self.eventsDir, accounts.map(\.label))
            await Task.detached {
                for label in labels { EventIngestor(db: db, eventsDir: eventsDir).rebuildAll(account: label, now: Date()) }
            }.value
            await reload()
        }
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.ingestInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.reload() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Recarregamentos rodam um de cada vez, na ordem pedida; cada um usa o período do momento em que começa.
    public func reload(now: Date? = nil) async {
        let previous = reloadTask
        let task = Task { @MainActor in
            await previous?.value
            await performReload(now: now ?? Date())
        }
        reloadTask = task
        await task.value
    }

    private func performReload(now: Date) async {
        let period = self.period
        let db = self.db
        let eventsDir = self.eventsDir
        let labels = accounts.map(\.label)
        let scanTitles = lastTitleScan.map { now.timeIntervalSince($0) > Self.titleScanInterval } ?? true
        if scanTitles { lastTitleScan = now }
        let range = period.range(calendar: calendar)
        let intervals = await Task.detached {
            let ingestor = EventIngestor(db: db, eventsDir: eventsDir)
            for label in labels { ingestor.ingest(account: label, now: now) }
            await resolvePendingProjects(db: db)
            if scanTitles {
                for session in db.untitledSessions() {
                    if let title = readSessionTitle(transcriptPath: session.transcriptPath) {
                        db.setSessionTitle(title, session: session.session, account: session.account)
                    }
                }
            }
            return db.intervals(from: range.start, to: range.end, now: now)
        }.value
        let report = makeReport(filter.applying(intervals), period: period, now: now, calendar: calendar)
        let list = makeReport(ReportFilter(accounts: filter.accounts).applying(intervals), period: period,
                              now: now, calendar: calendar).projects
        sessionTitles = db.sessionTitles(list.flatMap { $0.sessions.map(\.sessionId) })
        self.report = report
        listProjects = list
    }

    public func settingsURL(for account: Account) -> URL {
        URL(fileURLWithPath: account.directory).appendingPathComponent("settings.json")
    }

    public func refreshHooksActive() {
        var result: [String: Bool] = [:]
        for account in accounts {
            let data = (try? Data(contentsOf: settingsURL(for: account))) ?? Data("{}".utf8)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            result[account.label] = HooksInstaller.installed(in: json)
        }
        hooksActive = result
    }

    public var allHooksActive: Bool { accounts.allSatisfy { hooksActive[$0.label] == true } }

    public func previewText() -> String {
        accounts.map { HooksInstaller.previewDiff(settings: settingsURL(for: $0), account: $0.label) }
            .joined(separator: "\n\n")
    }

    /// Ativa ou desativa os hooks nas duas contas. Ao ativar, o histórico é reimportado até agora,
    /// para não sobrar buraco entre a importação inicial e o início do registro pelos hooks.
    public func setHooks(active: Bool) async throws {
        let now = Date()
        for account in accounts {
            if active {
                try HooksInstaller.install(settings: settingsURL(for: account), account: account.label, now: now)
                // Reativar não move a data original de ativação.
                if db.ingestState(account: account.label).hooksInstalledAt == nil {
                    db.setHooksInstalled(now, account: account.label)
                }
            } else {
                try HooksInstaller.uninstall(settings: settingsURL(for: account), now: now)
                db.setHooksInstalled(nil, account: account.label)
            }
        }
        refreshHooksActive()
        if active {
            importing = true
            let importer = HistoryImporter(db: db)
            for account in accounts {
                await Task.detached { await importer.importHistory(account: account, before: now, force: true) }.value
                db.setHistoryImported(now, account: account.label)
            }
            importing = false
        }
        await reload()
    }
}
