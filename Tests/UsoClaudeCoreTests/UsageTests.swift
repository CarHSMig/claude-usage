import Foundation
import Testing
@testable import UsoClaudeCore

private let fixture = #"{"five_hour":{"utilization":54.0,"resets_at":"2026-10-27T04:50:00.499950+00:00"},"seven_day":{"utilization":30.0,"resets_at":"2026-11-02T01:00:00.499973+00:00"},"tangelo":null}"#

private func usage(session: Double, weekly: Double) -> Usage {
    Usage(session: LimitWindow(utilization: session, resetsAt: nil), weekly: LimitWindow(utilization: weekly, resetsAt: nil))
}

@Test func parsesFractionalSecondsAndOffset() throws {
    let u = try parseUsage(Data(fixture.utf8))
    #expect(u.session.utilization == 54 && u.weekly.utilization == 30)
    let expected = ISO8601DateFormatter().date(from: "2026-10-27T04:50:00Z")!.addingTimeInterval(0.49995)
    #expect(abs(u.session.resetsAt!.timeIntervalSince(expected)) < 0.001)
}

@Test func nullResetsAtIsNil() throws {
    let json = #"{"five_hour":{"utilization":0.0,"resets_at":null},"seven_day":{"utilization":100.0,"resets_at":"2026-10-29T10:00:00.083054+00:00"}}"#
    let u = try parseUsage(Data(json.utf8))
    #expect(u.session.resetsAt == nil)
    #expect(u.weekly.resetsAt != nil)
}

@Test func levels() {
    #expect(level(for: 49.9) == .green)
    #expect(level(for: 50) == .yellow)
    #expect(level(for: 80) == .yellow)
    #expect(level(for: 80.1) == .red)
}

@Test func recommendsLowerWeekly() {
    #expect(recommended(["claude": usage(session: 0, weekly: 100), "proteo": usage(session: 54, weekly: 30)]) == "proteo")
}

@Test func tieBreaksOnSession() {
    #expect(recommended(["a": usage(session: 70, weekly: 40), "b": usage(session: 10, weekly: 43)]) == "b")
}

@Test func neverRecommendsExhaustedWhenOtherHasRoom() {
    #expect(recommended(["a": usage(session: 100, weekly: 10), "b": usage(session: 20, weekly: 60)]) == "b")
}

@Test func noRecommendationWhenBothExhausted() {
    #expect(recommended(["a": usage(session: 0, weekly: 100), "b": usage(session: 10, weekly: 100)]) == nil)
}

@Test func sessionResetTextFormats() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(sessionResetText(now.addingTimeInterval(2 * 3600 + 40 * 60), now: now) == "em 2h40")
    #expect(sessionResetText(now.addingTimeInterval(35 * 60), now: now) == "em 35min")
    #expect(sessionResetText(nil, now: now) == "—")
}

@Test func weeklyResetTextFormats() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    let date = ISO8601DateFormatter().date(from: "2026-11-02T01:00:00Z")!
    #expect(weeklyResetText(date, calendar: cal) == "dom 22:00")
    #expect(weeklyResetText(nil, calendar: cal) == "—")
}

@Test func roundedHundredIsExhausted() {
    // 99,6% aparece como "100%" no anel, então não pode ser recomendada.
    #expect(recommended(["a": usage(session: 99.6, weekly: 10), "b": usage(session: 20, weekly: 60)]) == "b")
    #expect(recommended(["a": usage(session: 10, weekly: 99.5), "b": usage(session: 20, weekly: 60)]) == "b")
    #expect(displayPercent(99.4) == 99 && displayPercent(99.6) == 100)
}
