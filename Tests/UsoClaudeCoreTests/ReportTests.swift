import Foundation
import Testing
@testable import UsoClaudeCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    c.firstWeekday = 2
    return c
}()

/// Data local em São Paulo: "2026-10-26 13:30".
private func d(_ s: String) -> Date {
    let f = DateFormatter()
    f.calendar = cal
    f.timeZone = cal.timeZone
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}

private func si(_ start: String, _ end: String?, session: String = "s", account: String = "claude",
                project: String = "proteo") -> StoredInterval {
    StoredInterval(account: account, sessionId: session, project: project, start: d(start), end: end.map(d), source: "hook")
}

@Test func midnightCrossingSplitsDays() {
    let intervals = [si("2026-10-26 23:50", "2026-10-27 00:20")]
    let week = makeReport(intervals, period: .week(d("2026-10-26 12:00")), now: d("2026-10-28 12:00"), calendar: cal)
    #expect(week.buckets[0].byAccount["claude"] == 600)
    #expect(week.buckets[1].byAccount["claude"] == 1200)
    #expect(week.total == 1800)
}

@Test func hourBucketsForDay() {
    let report = makeReport([si("2026-10-26 13:30", "2026-10-26 14:15")], period: .day(d("2026-10-26 08:00")),
                            now: d("2026-10-27 00:00"), calendar: cal)
    #expect(report.buckets.count == 24)
    #expect(report.buckets[13].byAccount["claude"] == 1800)
    #expect(report.buckets[14].byAccount["claude"] == 900)
    #expect(report.buckets[14].byProject["proteo"] == 900)
}

@Test func sameSessionOverlapCountsOnce() {
    let intervals = [si("2026-10-26 10:00", "2026-10-26 11:00"), si("2026-10-26 10:30", "2026-10-26 11:30")]
    #expect(makeReport(intervals, period: .day(d("2026-10-26 08:00")), now: d("2026-10-27 00:00"), calendar: cal).total == 5400)
}

@Test func parallelSessionsSum() {
    let intervals = [si("2026-10-26 10:00", "2026-10-26 11:00", session: "a"),
                     si("2026-10-26 10:00", "2026-10-26 11:00", session: "b", project: "outro")]
    let report = makeReport(intervals, period: .day(d("2026-10-26 08:00")), now: d("2026-10-27 00:00"), calendar: cal)
    #expect(report.total == 7200)
    #expect(report.projects.map(\.project).sorted() == ["outro", "proteo"])
}

@Test func openIntervalCountsToNow() {
    let report = makeReport([si("2026-10-26 10:00", nil)], period: .day(d("2026-10-26 08:00")),
                            now: d("2026-10-26 10:20"), calendar: cal)
    #expect(report.total == 1200)
}

@Test func weekStartsMonday() {
    let range = ReportPeriod.week(d("2026-10-28 15:00")).range(calendar: cal)
    #expect(range.start == d("2026-10-26 00:00"))
    #expect(range.end == d("2026-11-02 00:00"))
}

@Test func previousMonth() {
    let previous = ReportPeriod.month(d("2026-10-15 12:00")).previous(calendar: cal)
    #expect(previous.range(calendar: cal).start == d("2026-09-01 00:00"))
    #expect(previous.title(calendar: cal) == "set 2026")
}

@Test func periodTitles() {
    #expect(ReportPeriod.day(d("2026-10-26 12:00")).title(calendar: cal) == "seg, 26 out 2026")
    #expect(ReportPeriod.week(d("2026-10-28 12:00")).title(calendar: cal) == "26 out – 1 nov 2026")
    #expect(ReportPeriod.custom(d("2026-09-01 00:00"), d("2026-10-15 00:00")).title(calendar: cal) == "01/09/2026 – 15/10/2026")
}

@Test func customPeriodIncludesEndDayAndAverages() {
    let period = ReportPeriod.custom(d("2026-10-01 00:00"), d("2026-10-02 00:00"))
    #expect(period.range(calendar: cal).end == d("2026-10-03 00:00"))
    let report = makeReport([si("2026-10-02 10:00", "2026-10-02 12:00")], period: period, now: d("2026-10-27 00:00"), calendar: cal)
    #expect(report.buckets.count == 2)
    #expect(report.averagePerDay == 3600)
}

@Test func projectsSortedWithSessions() {
    let intervals = [si("2026-10-26 10:00", "2026-10-26 10:30", session: "a", project: "pequeno"),
                     si("2026-10-26 11:00", "2026-10-26 13:00", session: "b", account: "proteo"),
                     si("2026-10-26 14:00", "2026-10-26 14:30", session: "c")]
    let report = makeReport(intervals, period: .day(d("2026-10-26 08:00")), now: d("2026-10-27 00:00"), calendar: cal)
    #expect(report.projects.map(\.project) == ["proteo", "pequeno"])
    #expect(report.projects[0].byAccount == ["proteo": 7200, "claude": 1800])
    #expect(report.projects[0].sessions.map(\.sessionId) == ["b", "c"])
}

@Test func formatsHours() {
    #expect(formatHours(5 * 3600 + 47 * 60) == "5h 47min")
    #expect(formatHours(42 * 60) == "42min")
    #expect(formatHours(0) == "0min")
    #expect(formatHours(3 * 3600) == "3h 00min")
}

@Test func selectedBucketsSum() {
    let report = makeReport([si("2026-10-26 13:30", "2026-10-26 14:15"),
                             si("2026-10-26 16:00", "2026-10-26 16:20", session: "p", account: "proteo")],
                            period: .day(d("2026-10-26 08:00")), now: d("2026-10-27 00:00"), calendar: cal)
    let sum = selectionSummary(report.buckets, selected: [13, 14, 16])
    #expect(sum.total == 3900)
    #expect(sum.byAccount == ["claude": 2700, "proteo": 1200])
    #expect(selectionSummary(report.buckets, selected: []).total == 0)
    #expect(selectionSummary(report.buckets, selected: [99]).total == 0)
}
