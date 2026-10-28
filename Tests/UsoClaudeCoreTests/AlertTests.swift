import Foundation
import Testing
@testable import UsoClaudeCore

private let now = ISO8601DateFormatter().date(from: "2026-10-27T03:00:00Z")!
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    return c
}()

private func usage(_ session: Double, _ weekly: Double, sessionResets: Double? = 160, weeklyResets: Double? = 3 * 1440) -> Usage {
    Usage(session: LimitWindow(utilization: session, resetsAt: sessionResets.map { now.addingTimeInterval($0 * 60) }),
          weekly: LimitWindow(utilization: weekly, resetsAt: weeklyResets.map { now.addingTimeInterval($0 * 60) }))
}

@Test func crossesOnceAt80() {
    var notified: [String: Double] = [:]
    let first = evaluateAlerts(["proteo": usage(96, 31), "claude": usage(0, 100)], notified: &notified, now: now, calendar: cal)
    #expect(first.map(\.title).contains("proteo: sessão em 96%"))
    let again = evaluateAlerts(["proteo": usage(97, 31), "claude": usage(0, 100)], notified: &notified, now: now, calendar: cal)
    #expect(again.isEmpty)
}

@Test func belowThresholdNoAlert() {
    var notified: [String: Double] = [:]
    #expect(evaluateAlerts(["proteo": usage(79.4, 79.4)], notified: &notified, now: now, calendar: cal).isEmpty)
}

@Test func suggestsOtherAccountWithRoom() {
    var notified: [String: Double] = [:]
    let alerts = evaluateAlerts(["proteo": usage(85, 31), "claude": usage(10, 40)], notified: &notified, now: now, calendar: cal)
    #expect(alerts == [LimitAlert(title: "proteo: sessão em 85%",
                                  body: "Renova em 2h40. Use a claude (sessão 10% · semana 40%).")])
}

@Test func noRoomAnywhereSaysWhenOtherRenews() {
    var notified: [String: Double] = [:]
    let alerts = evaluateAlerts(["proteo": usage(96, 31), "claude": usage(0, 100, weeklyResets: 2 * 1440 + 240)],
                                notified: &notified, now: now, calendar: cal)
    // claude semana 100% também gera o próprio aviso; o da proteo explica que não há folga.
    let proteo = alerts.first { $0.title.hasPrefix("proteo") }
    #expect(proteo?.body == "Renova em 2h40. Nenhuma outra conta com folga: claude renova qui 04:00.")
}

@Test func resetAfterNotifiedAlertsAndRearms() {
    var notified: [String: Double] = [:]
    _ = evaluateAlerts(["proteo": usage(96, 31)], notified: &notified, now: now, calendar: cal)
    let reset = evaluateAlerts(["proteo": usage(3, 31, sessionResets: 300)], notified: &notified, now: now, calendar: cal)
    #expect(reset == [LimitAlert(title: "proteo: sessão renovada", body: "O limite da sessão voltou a ficar disponível.")])
    let again = evaluateAlerts(["proteo": usage(82, 31, sessionResets: 300)], notified: &notified, now: now, calendar: cal)
    #expect(again.map(\.title) == ["proteo: sessão em 82%"])
}

@Test func weeklyAlertUsesWeeklyWording() {
    var notified: [String: Double] = [:]
    let alerts = evaluateAlerts(["claude": usage(0, 100, weeklyResets: 2 * 1440 + 240)], notified: &notified, now: now, calendar: cal)
    #expect(alerts == [LimitAlert(title: "claude: semana em 100%",
                                  body: "Renova qui 04:00. Nenhuma outra conta com folga.")])
}
