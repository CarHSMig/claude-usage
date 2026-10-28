/// Filtro do relatório por projeto e por conta. Conjunto vazio = sem filtro naquela dimensão.
public struct ReportFilter: Codable, Sendable, Equatable {
    public var projects: Set<String>
    public var accounts: Set<String>

    public init(projects: Set<String> = [], accounts: Set<String> = []) {
        self.projects = projects
        self.accounts = accounts
    }

    public var isEmpty: Bool { projects.isEmpty && accounts.isEmpty }

    public func applying(_ intervals: [StoredInterval]) -> [StoredInterval] {
        intervals.filter {
            (projects.isEmpty || projects.contains($0.project)) && (accounts.isEmpty || accounts.contains($0.account))
        }
    }

    public mutating func toggleProject(_ project: String) {
        if projects.remove(project) == nil { projects.insert(project) }
    }

    public mutating func toggleAccount(_ account: String) {
        if accounts.remove(account) == nil { accounts.insert(account) }
    }
}
