import Foundation

/// Tempo até a sessão renovar: "em 2h40", "em 35min" ou "—".
public func sessionResetText(_ resetsAt: Date?, now: Date) -> String {
    guard let resetsAt else { return "—" }
    let minutes = max(0, Int((resetsAt.timeIntervalSince(now) / 60).rounded()))
    if minutes < 60 { return "em \(minutes)min" }
    return String(format: "em %dh%02d", minutes / 60, minutes % 60)
}

/// Dia e hora em que o limite semanal renova: "dom 22:00" ou "—".
public func weeklyResetText(_ resetsAt: Date?, calendar: Calendar = .current) -> String {
    guard let resetsAt else { return "—" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "pt_BR")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "EEE HH:mm"
    return formatter.string(from: resetsAt).replacingOccurrences(of: ".", with: "").lowercased()
}
