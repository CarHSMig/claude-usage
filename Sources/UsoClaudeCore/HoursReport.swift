import Foundation

public enum ReportPeriod: Sendable, Equatable {
    case day(Date)
    case week(Date)
    case month(Date)
    /// De/até, os dois dias inclusive.
    case custom(Date, Date)

    public func range(calendar: Calendar) -> (start: Date, end: Date) {
        switch self {
        case .day(let date):
            let start = calendar.startOfDay(for: date)
            return (start, calendar.date(byAdding: .day, value: 1, to: start)!)
        case .week(let date):
            let interval = calendar.dateInterval(of: .weekOfYear, for: date)!
            return (interval.start, interval.end)
        case .month(let date):
            let interval = calendar.dateInterval(of: .month, for: date)!
            return (interval.start, interval.end)
        case .custom(let from, let to):
            let start = calendar.startOfDay(for: min(from, to))
            let lastDay = calendar.startOfDay(for: max(from, to))
            return (start, calendar.date(byAdding: .day, value: 1, to: lastDay)!)
        }
    }

    public func previous(calendar: Calendar) -> ReportPeriod { shifted(by: -1, calendar: calendar) }
    public func next(calendar: Calendar) -> ReportPeriod { shifted(by: 1, calendar: calendar) }

    private func shifted(by step: Int, calendar: Calendar) -> ReportPeriod {
        switch self {
        case .day(let date): return .day(calendar.date(byAdding: .day, value: step, to: date)!)
        case .week(let date): return .week(calendar.date(byAdding: .day, value: 7 * step, to: date)!)
        case .month(let date): return .month(calendar.date(byAdding: .month, value: step, to: date)!)
        case .custom(let from, let to):
            let days = (calendar.dateComponents([.day], from: calendar.startOfDay(for: from),
                                                to: calendar.startOfDay(for: to)).day ?? 0) + 1
            return .custom(calendar.date(byAdding: .day, value: days * step, to: from)!,
                           calendar.date(byAdding: .day, value: days * step, to: to)!)
        }
    }

    public func title(calendar: Calendar) -> String {
        func format(_ pattern: String, _ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "pt_BR")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = pattern
            return formatter.string(from: date).replacingOccurrences(of: ".", with: "").lowercased()
        }
        switch self {
        case .day(let date):
            return format("EEE, d MMM yyyy", date)
        case .week:
            let r = range(calendar: calendar)
            let last = calendar.date(byAdding: .day, value: -1, to: r.end)!
            let sameMonth = calendar.isDate(r.start, equalTo: last, toGranularity: .month)
            let sameYear = calendar.isDate(r.start, equalTo: last, toGranularity: .year)
            let first = sameMonth ? format("d", r.start) : format(sameYear ? "d MMM" : "d MMM yyyy", r.start)
            return "\(first)\(sameMonth ? "–" : " – ")\(format("d MMM yyyy", last))"
        case .month(let date):
            return format("MMM yyyy", date)
        case .custom(let from, let to):
            return "\(format("dd/MM/yyyy", min(from, to))) – \(format("dd/MM/yyyy", max(from, to)))"
        }
    }

    var hourly: Bool {
        if case .day = self { return true }
        return false
    }
}

public struct Bucket: Sendable {
    public let start: Date
    public let end: Date
    public let byAccount: [String: TimeInterval]
    public let byProject: [String: TimeInterval]
    public var total: TimeInterval { byAccount.values.reduce(0, +) }
}

public struct SessionRow: Sendable, Identifiable {
    public let sessionId: String
    public let account: String
    public let start: Date
    public let seconds: TimeInterval
    public var id: String { sessionId }
}

public struct ProjectRow: Sendable, Identifiable {
    public let project: String
    public let byAccount: [String: TimeInterval]
    public let sessions: [SessionRow]
    public var total: TimeInterval { byAccount.values.reduce(0, +) }
    public var id: String { project }
}

public struct HoursReport: Sendable {
    public let total: TimeInterval
    public let buckets: [Bucket]
    public let projects: [ProjectRow]
    public let averagePerDay: TimeInterval
}

/// Monta o relatório: intervalos abertos contam até `now`, tudo é recortado ao período,
/// intervalos da mesma sessão são unidos (sem contar duas vezes) e sessões diferentes somam.
public func makeReport(_ intervals: [StoredInterval], period: ReportPeriod, now: Date, calendar: Calendar) -> HoursReport {
    let range = period.range(calendar: calendar)

    // Fronteiras dos baldes: horas no Dia, dias nos demais.
    var edges = [range.start]
    while let last = edges.last, last < range.end {
        edges.append(calendar.date(byAdding: period.hourly ? .hour : .day, value: 1, to: last)!)
    }
    var bucketAccount = Array(repeating: [String: TimeInterval](), count: edges.count - 1)
    var bucketProject = bucketAccount

    struct Key: Hashable { let session: String; let account: String; let project: String }
    var segmentsByKey: [Key: [(Date, Date)]] = [:]
    for i in intervals {
        let start = max(i.start, range.start)
        let end = min(i.end ?? now, range.end)
        guard end > start else { continue }
        segmentsByKey[Key(session: i.sessionId, account: i.account, project: i.project), default: []].append((start, end))
    }

    var projectAccount: [String: [String: TimeInterval]] = [:]
    var projectSessions: [String: [SessionRow]] = [:]
    var total: TimeInterval = 0

    for (key, segments) in segmentsByKey {
        // União dos trechos da sessão.
        var merged: [(Date, Date)] = []
        for seg in segments.sorted(by: { $0.0 < $1.0 }) {
            if let last = merged.last, seg.0 <= last.1 {
                merged[merged.count - 1].1 = max(last.1, seg.1)
            } else {
                merged.append(seg)
            }
        }
        var sessionSeconds: TimeInterval = 0
        for (start, end) in merged {
            sessionSeconds += end.timeIntervalSince(start)
            for b in 0..<(edges.count - 1) where edges[b] < end && edges[b + 1] > start {
                let overlap = min(end, edges[b + 1]).timeIntervalSince(max(start, edges[b]))
                bucketAccount[b][key.account, default: 0] += overlap
                bucketProject[b][key.project, default: 0] += overlap
            }
        }
        total += sessionSeconds
        projectAccount[key.project, default: [:]][key.account, default: 0] += sessionSeconds
        projectSessions[key.project, default: []].append(
            SessionRow(sessionId: key.session, account: key.account, start: merged[0].0, seconds: sessionSeconds))
    }

    let buckets = (0..<(edges.count - 1)).map {
        Bucket(start: edges[$0], end: edges[$0 + 1], byAccount: bucketAccount[$0], byProject: bucketProject[$0])
    }
    let projects = projectAccount.map { project, byAccount in
        ProjectRow(project: project, byAccount: byAccount,
                   sessions: (projectSessions[project] ?? []).sorted { $0.start < $1.start })
    }.sorted { $0.total > $1.total }
    let days = max(1, calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 1)
    return HoursReport(total: total, buckets: buckets, projects: projects, averagePerDay: total / Double(days))
}

/// "5h 47min", "42min", "0min".
public func formatHours(_ seconds: TimeInterval) -> String {
    let minutes = Int((seconds / 60).rounded())
    if minutes < 60 { return "\(minutes)min" }
    return String(format: "%dh %02dmin", minutes / 60, minutes % 60)
}

/// Soma das colunas selecionadas no gráfico (índices fora do intervalo são ignorados).
public func selectionSummary(_ buckets: [Bucket], selected: Set<Int>) -> (total: TimeInterval, byAccount: [String: TimeInterval]) {
    var byAccount: [String: TimeInterval] = [:]
    for i in selected where buckets.indices.contains(i) {
        byAccount.merge(buckets[i].byAccount, uniquingKeysWith: +)
    }
    return (byAccount.values.reduce(0, +), byAccount)
}
