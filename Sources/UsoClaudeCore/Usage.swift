import Foundation

/// Um limite (sessão de 5h ou semanal): % usado (0–100) e quando renova.
public struct LimitWindow: Sendable, Equatable {
    public let utilization: Double
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public struct Usage: Sendable, Equatable {
    public let session: LimitWindow
    public let weekly: LimitWindow

    public init(session: LimitWindow, weekly: LimitWindow) {
        self.session = session
        self.weekly = weekly
    }
}

private struct RawWindow: Decodable {
    let utilization: Double
    let resets_at: String?
}

private struct RawUsage: Decodable {
    let five_hour: RawWindow
    let seven_day: RawWindow
}

/// Lê a resposta de `/api/oauth/usage`, ignorando os campos que não usamos.
public func parseUsage(_ data: Data) throws -> Usage {
    let raw = try JSONDecoder().decode(RawUsage.self, from: data)
    func window(_ w: RawWindow) -> LimitWindow {
        LimitWindow(utilization: w.utilization, resetsAt: w.resets_at.flatMap(parseISODate))
    }
    return Usage(session: window(raw.five_hour), weekly: window(raw.seven_day))
}

func parseISODate(_ string: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFraction.date(from: string) { return date }
    return ISO8601DateFormatter().date(from: string)
}
