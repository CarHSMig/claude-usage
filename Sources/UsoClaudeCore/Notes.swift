import Foundation
import SQLite3

public struct NoteLine: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var done: Bool

    public init(id: UUID = UUID(), text: String = "", done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }
}

public enum NoteLineKind: Sendable {
    /// Tarefa com checkbox (o padrão).
    case item
    /// Título de grupo: linha terminada em ":".
    case heading
    /// Observação solta: linha começando com "-".
    case remark
}

public func noteLineKind(_ text: String) -> NoteLineKind {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("-") { return .remark }
    if trimmed.count > 1, trimmed.hasSuffix(":") { return .heading }
    return .item
}

/// Pendentes e feitas: só tarefas com texto contam.
public func noteCounts(_ lines: [NoteLine]) -> (pending: Int, done: Int) {
    let items = lines.filter { noteLineKind($0.text) == .item && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    let done = items.filter(\.done).count
    return (items.count - done, done)
}

/// A nota viva: `day` é o dia a que o conteúdo pertence; `edited` diz se foi mexida nesse dia.
public struct LiveNote: Codable, Equatable, Sendable {
    public var lines: [NoteLine]
    public var day: String
    public var edited: Bool

    public init(lines: [NoteLine], day: String, edited: Bool) {
        self.lines = lines
        self.day = day
        self.edited = edited
    }
}

/// "2026-10-27" no fuso do calendário.
public func dayKey(_ date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}

/// Virada do dia: guarda o snapshot do dia anterior (se a nota foi mexida e tem texto),
/// tira as tarefas feitas e mantém o resto.
public func rollover(_ note: LiveNote, today: String) -> (live: LiveNote, snapshot: (day: String, lines: [NoteLine])?) {
    guard note.day != today else { return (note, nil) }
    let hasText = note.lines.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    let snapshot = note.edited && hasText ? (note.day, note.lines) : nil
    let remaining = note.lines.filter { !($0.done && noteLineKind($0.text) == .item) }
    return (LiveNote(lines: remaining.isEmpty ? [NoteLine()] : remaining, day: today, edited: false), snapshot)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Notas no mesmo arquivo SQLite das horas, em tabelas próprias. Todas as chamadas passam por uma fila serial.
public final class NotesDB: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "UsoClaude.NotesDB")

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            throw NSError(domain: "NotesDB", code: 1, userInfo: [NSLocalizedDescriptionKey: "não abriu \(url.path)"])
        }
        sqlite3_busy_timeout(handle, 2000)
        sqlite3_exec(handle, """
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS notes_live(id INTEGER PRIMARY KEY CHECK(id = 1), lines TEXT, day TEXT, edited INTEGER);
        CREATE TABLE IF NOT EXISTS notes_snapshots(day TEXT PRIMARY KEY, lines TEXT);
        """, nil, nil, nil)
    }

    deinit { sqlite3_close(handle) }

    public func loadLive() -> LiveNote? {
        queue.sync {
            rows("SELECT lines, day, edited FROM notes_live WHERE id = 1", []) { stmt in
                guard let lines = decode(stmt, 0), let day = text(stmt, 1) else { return nil }
                return LiveNote(lines: lines, day: day, edited: sqlite3_column_int(stmt, 2) != 0)
            }.first ?? nil
        }
    }

    public func saveLive(_ note: LiveNote) {
        queue.sync {
            run("INSERT OR REPLACE INTO notes_live(id, lines, day, edited) VALUES(1, ?, ?, ?)",
                [encode(note.lines), note.day, note.edited ? "1" : "0"])
        }
    }

    public func saveSnapshot(day: String, lines: [NoteLine]) {
        queue.sync { run("INSERT OR REPLACE INTO notes_snapshots(day, lines) VALUES(?, ?)", [day, encode(lines)]) }
    }

    /// Dias com snapshot, do mais antigo ao mais novo.
    public func snapshotDays() -> [String] {
        queue.sync { rows("SELECT day FROM notes_snapshots ORDER BY day", []) { text($0, 0) }.compactMap { $0 } }
    }

    public func snapshot(day: String) -> [NoteLine]? {
        queue.sync { rows("SELECT lines FROM notes_snapshots WHERE day = ?", [day]) { decode($0, 0) }.first ?? nil }
    }

    // MARK: SQLite

    private func encode(_ lines: [NoteLine]) -> String {
        String(decoding: (try? JSONEncoder().encode(lines)) ?? Data("[]".utf8), as: UTF8.self)
    }

    private func decode(_ stmt: OpaquePointer?, _ column: Int32) -> [NoteLine]? {
        text(stmt, column).flatMap { try? JSONDecoder().decode([NoteLine].self, from: Data($0.utf8)) }
    }

    private func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }

    private func prepare(_ sql: String, _ params: [String]) -> OpaquePointer? {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        for (i, value) in params.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), value, -1, SQLITE_TRANSIENT)
        }
        return stmt
    }

    private func run(_ sql: String, _ params: [String]) {
        let stmt = prepare(sql, params)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    private func rows<T>(_ sql: String, _ params: [String], _ map: (OpaquePointer?) -> T) -> [T] {
        let stmt = prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var result: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(map(stmt)) }
        return result
    }
}

/// Estado da aba Notas: a nota viva (editável) e a navegação pelos snapshots dos dias anteriores.
@MainActor
public final class NotesStore: ObservableObject {
    @Published public private(set) var lines: [NoteLine] = [NoteLine()]
    @Published public private(set) var snapshotDays: [String] = []
    /// `nil` = hoje (nota viva); senão, o dia do snapshot em exibição.
    @Published public private(set) var viewingDay: String?

    public let calendar: Calendar
    private let db: NotesDB
    private let now: () -> Date
    private var live: LiveNote
    private var timer: Timer?

    public init(db: NotesDB, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.db = db
        self.calendar = calendar
        self.now = now
        live = db.loadLive() ?? LiveNote(lines: [NoteLine()], day: dayKey(now(), calendar: calendar), edited: false)
        lines = live.lines
        snapshotDays = db.snapshotDays()
        checkRollover()
    }

    /// Confere a virada do dia a cada minuto (o snapshot sai mesmo sem edição depois da meia-noite).
    public func start() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkRollover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func checkRollover() {
        let result = rollover(live, today: dayKey(now(), calendar: calendar))
        guard result.live != live else { return }
        if let snapshot = result.snapshot {
            db.saveSnapshot(day: snapshot.day, lines: snapshot.lines)
            snapshotDays = db.snapshotDays()
        }
        live = result.live
        lines = live.lines
        db.saveLive(live)
    }

    public func update(_ newLines: [NoteLine]) {
        checkRollover()
        live.lines = newLines.isEmpty ? [NoteLine()] : newLines
        live.edited = true
        lines = live.lines
        db.saveLive(live)
    }

    public var viewedLines: [NoteLine] {
        guard let day = viewingDay else { return lines }
        return db.snapshot(day: day) ?? []
    }

    /// Dias anteriores ao que está em exibição (hoje = depois de todos os snapshots).
    private var currentIndex: Int { viewingDay.flatMap { snapshotDays.firstIndex(of: $0) } ?? snapshotDays.count }

    public var canGoPrevious: Bool { currentIndex > 0 }
    public var canGoNext: Bool { viewingDay != nil }

    public func goPrevious() {
        guard canGoPrevious else { return }
        viewingDay = snapshotDays[currentIndex - 1]
    }

    public func goNext() {
        guard canGoNext else { return }
        let next = currentIndex + 1
        viewingDay = next < snapshotDays.count ? snapshotDays[next] : nil
    }

    public func goToday() { viewingDay = nil }
}
