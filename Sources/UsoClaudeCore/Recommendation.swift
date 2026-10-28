public enum Level: Sendable { case green, yellow, red }

public func level(for utilization: Double) -> Level {
    if utilization < 50 { return .green }
    if utilization <= 80 { return .yellow }
    return .red
}

/// % inteiro mostrado no anel. A recomendação usa o mesmo arredondamento,
/// para que uma conta exibida como "100%" conte como esgotada.
public func displayPercent(_ utilization: Double) -> Int {
    Int(utilization.rounded())
}

/// Rótulo da conta com mais folga, ou `nil` se nenhuma tiver.
/// Conta com algum limite esgotado nunca é recomendada; entre as demais vence o menor % semanal,
/// e diferenças semanais abaixo de 5 pontos são desempatadas pela sessão.
public func recommended(_ usages: [String: Usage]) -> String? {
    let available = usages.filter { displayPercent($0.value.session.utilization) < 100
        && displayPercent($0.value.weekly.utilization) < 100 }
    let byWeekly = available.sorted { $0.value.weekly.utilization < $1.value.weekly.utilization }
    guard let first = byWeekly.first else { return nil }
    guard byWeekly.count > 1 else { return first.key }
    let second = byWeekly[1]
    if second.value.weekly.utilization - first.value.weekly.utilization < 5,
       second.value.session.utilization < first.value.session.utilization {
        return second.key
    }
    return first.key
}
