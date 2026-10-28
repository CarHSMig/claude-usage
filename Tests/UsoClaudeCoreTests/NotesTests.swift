import Foundation
import Testing
@testable import UsoClaudeCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    return c
}()

private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private func line(_ text: String, done: Bool = false) -> NoteLine { NoteLine(text: text, done: done) }

@Test func lineKinds() {
    #expect(noteLineKind("Cliente Proteo:") == .heading)
    #expect(noteLineKind("  Pessoal:  ") == .heading)
    #expect(noteLineKind("- aguardando suporte") == .remark)
    #expect(noteLineKind("Responder Ana") == .item)
    #expect(noteLineKind("") == .item)
}

@Test func dayKeyUsesCalendarTimeZone() {
    // 02:30 UTC ainda é dia 26 em São Paulo.
    #expect(dayKey(at("2026-10-27T02:30:00Z"), calendar: cal) == "2026-10-26")
    #expect(dayKey(at("2026-10-27T03:00:00Z"), calendar: cal) == "2026-10-27")
}

@Test func rolloverSnapshotsEditedDayAndDropsDoneItems() {
    let note = LiveNote(lines: [line("Proteo:"), line("Revisar PR", done: true), line("Responder Ana")],
                        day: "2026-10-26", edited: true)
    let result = rollover(note, today: "2026-10-27")
    #expect(result.snapshot?.day == "2026-10-26")
    #expect(result.snapshot?.lines == note.lines)
    #expect(result.live.lines.map(\.text) == ["Proteo:", "Responder Ana"])
    #expect(result.live.day == "2026-10-27")
    #expect(result.live.edited == false)
}

@Test func rolloverSameDayChangesNothing() {
    let note = LiveNote(lines: [line("a", done: true)], day: "2026-10-27", edited: true)
    let result = rollover(note, today: "2026-10-27")
    #expect(result.snapshot == nil)
    #expect(result.live == note)
}

@Test func rolloverWithoutEditsSkipsSnapshot() {
    let note = LiveNote(lines: [line("pendente")], day: "2026-10-25", edited: false)
    let result = rollover(note, today: "2026-10-27")
    #expect(result.snapshot == nil)
    #expect(result.live.lines.map(\.text) == ["pendente"])
}

@Test func rolloverOfBlankNoteSkipsSnapshotAndKeepsOneLine() {
    let note = LiveNote(lines: [line("   "), line("feito", done: true)], day: "2026-10-26", edited: true)
    let result = rollover(note, today: "2026-10-27")
    #expect(result.snapshot?.day == "2026-10-26")
    let empty = rollover(LiveNote(lines: [line("")], day: "2026-10-26", edited: true), today: "2026-10-27")
    #expect(empty.snapshot == nil)
    #expect(empty.live.lines.count == 1)
    #expect(rollover(LiveNote(lines: [line("x", done: true)], day: "2026-10-26", edited: true),
                     today: "2026-10-27").live.lines.count == 1)
}

@Test func noteCounts() {
    let lines = [line("Proteo:"), line("a", done: true), line("b"), line("- obs"), line("")]
    #expect(noteCounts(lines) == (pending: 1, done: 1))
}

@Test func notesDBRoundTrip() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID()).sqlite")
    let db = try NotesDB(url: url)
    #expect(db.loadLive() == nil)
    let live = LiveNote(lines: [line("a"), line("b", done: true)], day: "2026-10-27", edited: true)
    db.saveLive(live)
    db.saveSnapshot(day: "2026-10-25", lines: [line("x")])
    db.saveSnapshot(day: "2026-10-26", lines: [line("y")])
    db.saveSnapshot(day: "2026-10-26", lines: [line("z")])
    let reopened = try NotesDB(url: url)
    #expect(reopened.loadLive() == live)
    #expect(reopened.snapshotDays() == ["2026-10-25", "2026-10-26"])
    #expect(reopened.snapshot(day: "2026-10-26")?.map(\.text) == ["z"])
}

@MainActor @Test func storeEditsRollOverAndNavigate() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID()).sqlite")
    var now = at("2026-10-26T15:00:00Z")
    let store = NotesStore(db: try NotesDB(url: url), calendar: cal, now: { now })
    #expect(store.lines.count == 1)
    #expect(store.viewingDay == nil)

    store.update([line("Proteo:"), line("Revisar PR", done: true), line("Responder Ana")])
    now = at("2026-10-27T12:00:00Z")
    store.checkRollover()
    #expect(store.lines.map(\.text) == ["Proteo:", "Responder Ana"])
    #expect(store.snapshotDays == ["2026-10-26"])

    #expect(store.canGoNext == false)
    store.goPrevious()
    #expect(store.viewingDay == "2026-10-26")
    #expect(store.viewedLines.map(\.text) == ["Proteo:", "Revisar PR", "Responder Ana"])
    #expect(store.canGoPrevious == false)
    store.goNext()
    #expect(store.viewingDay == nil)
    #expect(store.viewedLines.map(\.text) == ["Proteo:", "Responder Ana"])

    // Editar depois da virada sem o timer ter rodado: a virada acontece antes de gravar.
    now = at("2026-10-28T12:00:00Z")
    store.update(store.lines + [line("Novo")])
    #expect(store.snapshotDays == ["2026-10-26"])  // o dia 27 não foi editado
    let reloaded = NotesStore(db: try NotesDB(url: url), calendar: cal, now: { now })
    #expect(reloaded.lines.map(\.text) == ["Proteo:", "Responder Ana", "Novo"])
}
