import Foundation

public struct LimitAlert: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

private enum WindowKind: String, CaseIterable {
    case session, weekly

    var name: String { self == .session ? "sessão" : "semana" }

    func window(_ usage: Usage) -> LimitWindow { self == .session ? usage.session : usage.weekly }

    func resetText(_ date: Date?, now: Date, calendar: Calendar) -> String {
        self == .session ? sessionResetText(date, now: now) : weeklyResetText(date, calendar: calendar)
    }
}

/// Avisos de limite: um por janela (sessão/semana) de cada conta ao passar de `threshold`, e outro quando
/// essa janela renova. `notified` guarda, por "conta.janela", o fim da janela já avisada (em minutos; -1 = sem data)
/// e deve ser persistido entre execuções para não repetir avisos.
public func evaluateAlerts(_ usages: [String: Usage], notified: inout [String: Double], threshold: Double = 80,
                           now: Date, calendar: Calendar) -> [LimitAlert] {
    func windowID(_ date: Date?) -> Double { date.map { ($0.timeIntervalSince1970 / 60).rounded() } ?? -1 }
    func hasRoom(_ usage: Usage) -> Bool {
        WindowKind.allCases.allSatisfy { Double(displayPercent($0.window(usage).utilization)) < threshold }
    }

    var alerts: [LimitAlert] = []
    for label in usages.keys.sorted() {
        let usage = usages[label]!
        for kind in WindowKind.allCases {
            let window = kind.window(usage)
            let key = "\(label).\(kind.rawValue)"
            let id = windowID(window.resetsAt)
            let percent = displayPercent(window.utilization)
            let over = Double(percent) >= threshold

            if over, notified[key] != id {
                notified[key] = id
                let others = usages.filter { $0.key != label }
                let roomy = others.filter { hasRoom($0.value) }
                var body = "Renova \(kind.resetText(window.resetsAt, now: now, calendar: calendar))."
                if let pick = recommended(roomy), let other = roomy[pick] {
                    body += " Use a \(pick) (sessão \(displayPercent(other.session.utilization))% · "
                        + "semana \(displayPercent(other.weekly.utilization))%)."
                } else if others.isEmpty {
                    body += " Nenhuma outra conta com folga."
                } else {
                    // Para cada outra conta, quando ela volta a ter folga: a última renovação entre as janelas cheias.
                    let renewals = others.keys.sorted().compactMap { name -> String? in
                        let blocking = WindowKind.allCases.filter {
                            Double(displayPercent($0.window(others[name]!).utilization)) >= threshold
                        }
                        guard let last = blocking.max(by: {
                            ($0.window(others[name]!).resetsAt ?? .distantPast) < ($1.window(others[name]!).resetsAt ?? .distantPast)
                        }) else { return nil }
                        return "\(name) renova \(last.resetText(last.window(others[name]!).resetsAt, now: now, calendar: calendar))"
                    }
                    body += " Nenhuma outra conta com folga: \(renewals.joined(separator: "; "))."
                }
                alerts.append(LimitAlert(title: "\(label): \(kind.name) em \(percent)%", body: body))
            } else if !over, let previous = notified[key], previous != id {
                notified[key] = nil
                alerts.append(LimitAlert(title: "\(label): \(kind.name) renovada",
                                         body: "O limite da \(kind.name) voltou a ficar disponível."))
            }
        }
    }
    return alerts
}
