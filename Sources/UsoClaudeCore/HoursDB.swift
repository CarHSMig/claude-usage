import Foundation
import SQLite3

public struct StoredInterval: Sendable, Equatable {
    public let account: String
    public let sessionId: String
    public let project: String
    public let start: Date
    public let end: Date?
    public let source: String

    public init(account: String, sessionId: String, project: String, start: Date, end: Date?, source: String) {
        self.account = account
        self.sessionId = sessionId
        self.project = project
        self.start = start
        self.end = end
        self.source = source
    }
}

public struct IngestState: Sendable {
    public let offset: UInt64
    /// Identificador do arquivo de eventos lido até `offset`; se mudar, o arquivo foi recriado.
    public let fileID: UInt64?
    public let historyImportedAt: Date?
    public let hooksInstalledAt: Date?
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Banco local das horas de IA. Todas as chamadas passam por uma fila serial.
public final class HoursDB: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "UsoClaude.HoursDB")

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            throw NSError(domain: "HoursDB", code: 1, userInfo: [NSLocalizedDescriptionKey: "não abriu \(url.path)"])
        }
        exec("""
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS events(account TEXT, session_id TEXT, ts REAL, event TEXT, cwd TEXT,
            transcript_path TEXT, tool_name TEXT, notification_type TEXT);
        CREATE INDEX IF NOT EXISTS events_session ON events(session_id);
        CREATE TABLE IF NOT EXISTS intervals(account TEXT, session_id TEXT, cwd TEXT, start REAL, end REAL, source TEXT);
        CREATE INDEX IF NOT EXISTS intervals_start ON intervals(start);
        CREATE INDEX IF NOT EXISTS intervals_session ON intervals(session_id);
        CREATE TABLE IF NOT EXISTS sessions(session_id TEXT PRIMARY KEY, account TEXT, title TEXT, transcript_path TEXT);
        CREATE TABLE IF NOT EXISTS projects(cwd TEXT PRIMARY KEY, project TEXT);
        CREATE TABLE IF NOT EXISTS ingest(account TEXT PRIMARY KEY, events_offset INTEGER DEFAULT 0,
            history_imported_at REAL, hooks_installed_at REAL);
        """)
        // Bancos criados antes desta coluna existir (o erro de coluna duplicada é ignorado).
        exec("ALTER TABLE ingest ADD COLUMN events_file_id INTEGER")
    }

    deinit { sqlite3_close(handle) }

    // MARK: Eventos

    public func insertEvents(_ events: [HookEvent], account: String) {
        insertEvents(events, account: account, extra: {})
    }

    private func insertEvents(_ events: [HookEvent], account: String, extra: () -> Void) {
        queue.sync {
            exec("BEGIN")
            for e in events {
                run("INSERT INTO events VALUES(?,?,?,?,?,?,?,?)",
                    [account, e.sessionId, e.ts.timeIntervalSince1970, e.event, e.cwd, e.transcriptPath,
                     e.toolName, e.notificationType])
                if let path = e.transcriptPath {
                    run("""
                    INSERT INTO sessions(session_id, account, transcript_path) VALUES(?,?,?)
                    ON CONFLICT(session_id) DO UPDATE SET transcript_path = excluded.transcript_path
                    """, [e.sessionId, account, path])
                }
            }
            extra()
            exec("COMMIT")
        }
    }

    public func events(session: String) -> [HookEvent] {
        queue.sync {
            query("""
            SELECT ts, event, session_id, cwd, transcript_path, tool_name, notification_type
            FROM events WHERE session_id = ? ORDER BY ts
            """, [session]) { row in
                HookEvent(ts: Date(timeIntervalSince1970: row.double(0)), event: row.string(1) ?? "",
                          sessionId: row.string(2) ?? "", cwd: row.string(3), transcriptPath: row.string(4),
                          toolName: row.string(5), notificationType: row.string(6))
            }
        }
    }

    // MARK: Intervalos

    /// Substitui os intervalos de uma sessão vindos de uma fonte (`hook` ou `import`).
    public func replaceIntervals(session: String, account: String, cwd: String?, _ intervals: [AIInterval], source: String) {
        queue.sync {
            exec("BEGIN")
            run("DELETE FROM intervals WHERE session_id = ? AND source = ?", [session, source])
            for i in intervals {
                run("INSERT INTO intervals VALUES(?,?,?,?,?,?)",
                    [account, session, cwd, i.start.timeIntervalSince1970, i.end?.timeIntervalSince1970, source])
            }
            exec("COMMIT")
        }
    }

    /// Intervalos que encostam no período [from, to). Intervalos abertos começados até `now` também entram.
    public func intervals(from: Date, to: Date, now: Date) -> [StoredInterval] {
        queue.sync {
            query("""
            SELECT i.account, i.session_id, i.cwd, p.project, i.start, i.end, i.source
            FROM intervals i LEFT JOIN projects p ON p.cwd = i.cwd
            WHERE i.start < ? AND COALESCE(i.end, ?) > ?
            ORDER BY i.start
            """, [to.timeIntervalSince1970, now.timeIntervalSince1970, from.timeIntervalSince1970]) { row in
                let cwd = row.string(2) ?? ""
                return StoredInterval(account: row.string(0) ?? "", sessionId: row.string(1) ?? "",
                                      project: row.string(3) ?? URL(fileURLWithPath: cwd).lastPathComponent,
                                      start: Date(timeIntervalSince1970: row.double(4)),
                                      end: row.isNull(5) ? nil : Date(timeIntervalSince1970: row.double(5)),
                                      source: row.string(6) ?? "")
            }
        }
    }

    public func hookSessions(account: String) -> [String] {
        queue.sync { query("SELECT DISTINCT session_id FROM events WHERE account = ?", [account]) { $0.string(0) ?? "" } }
    }

    /// Sessões de uma conta com intervalo ainda aberto (precisam ser reavaliadas pelo tempo de abandono).
    public func sessionsWithOpenIntervals(account: String) -> [String] {
        queue.sync {
            query("SELECT DISTINCT session_id FROM intervals WHERE account = ? AND end IS NULL", [account]) { $0.string(0) ?? "" }
        }
    }

    // MARK: Projetos e sessões

    public func setProject(_ project: String, forCwd cwd: String) {
        queue.sync {
            run("INSERT INTO projects VALUES(?,?) ON CONFLICT(cwd) DO UPDATE SET project = excluded.project", [cwd, project])
        }
    }

    public func project(forCwd cwd: String) -> String? {
        queue.sync { query("SELECT project FROM projects WHERE cwd = ?", [cwd]) { $0.string(0) }.first ?? nil }
    }

    public func knownProjects() -> [String] {
        queue.sync { query("SELECT DISTINCT project FROM projects", []) { $0.string(0) ?? "" } }
    }

    /// Pastas que aparecem nos intervalos e ainda não têm projeto resolvido.
    public func unresolvedCwds() -> [String] {
        queue.sync {
            query("""
            SELECT DISTINCT i.cwd FROM intervals i LEFT JOIN projects p ON p.cwd = i.cwd
            WHERE i.cwd IS NOT NULL AND p.project IS NULL
            """, []) { $0.string(0) ?? "" }
        }
    }

    public func setSessionTitle(_ title: String, session: String, account: String) {
        queue.sync {
            run("""
            INSERT INTO sessions(session_id, account, title) VALUES(?,?,?)
            ON CONFLICT(session_id) DO UPDATE SET title = excluded.title
            """, [session, account, title])
        }
    }

    public func sessionTitles(_ ids: [String]) -> [String: String] {
        queue.sync {
            var result: [String: String] = [:]
            for id in ids {
                if let title = query("SELECT title FROM sessions WHERE session_id = ?", [id], { $0.string(0) }).first ?? nil {
                    result[id] = title
                }
            }
            return result
        }
    }

    /// Sessões sem título que têm transcript conhecido (título é lido depois, do `ai-title`).
    public func untitledSessions() -> [(session: String, account: String, transcriptPath: String)] {
        queue.sync {
            query("SELECT session_id, account, transcript_path FROM sessions WHERE title IS NULL AND transcript_path IS NOT NULL", []) {
                ($0.string(0) ?? "", $0.string(1) ?? "", $0.string(2) ?? "")
            }
        }
    }

    // MARK: Estado de ingestão

    public func ingestState(account: String) -> IngestState {
        queue.sync {
            query("SELECT events_offset, history_imported_at, hooks_installed_at, events_file_id FROM ingest WHERE account = ?",
                  [account]) { row in
                IngestState(offset: UInt64(row.int64(0)), fileID: row.isNull(3) ? nil : UInt64(row.int64(3)),
                            historyImportedAt: row.isNull(1) ? nil : Date(timeIntervalSince1970: row.double(1)),
                            hooksInstalledAt: row.isNull(2) ? nil : Date(timeIntervalSince1970: row.double(2)))
            }.first ?? IngestState(offset: 0, fileID: nil, historyImportedAt: nil, hooksInstalledAt: nil)
        }
    }

    /// Grava os eventos lidos e o novo ponto de leitura numa única transação.
    public func commitIngest(_ events: [HookEvent], account: String, offset: UInt64, fileID: UInt64?) {
        insertEvents(events, account: account, extra: { [self] in
            run("INSERT INTO ingest(account) VALUES(?) ON CONFLICT(account) DO NOTHING", [account])
            run("UPDATE ingest SET events_offset = ?, events_file_id = ? WHERE account = ?",
                [Int64(offset), fileID.map { Int64(bitPattern: $0) }, account])
        })
    }

    /// Primeiro evento de hook de cada sessão da conta (turnos importados depois disso já estão nos hooks).
    public func firstHookEventTimes(account: String) -> [String: Date] {
        queue.sync {
            var result: [String: Date] = [:]
            for (session, ts) in query("SELECT session_id, MIN(ts) FROM events WHERE account = ? GROUP BY session_id", [account],
                                       { ($0.string(0) ?? "", $0.double(1)) }) {
                result[session] = Date(timeIntervalSince1970: ts)
            }
            return result
        }
    }

    public func setOffset(_ offset: UInt64, account: String) {
        upsertIngest(account: account, column: "events_offset", value: Int64(offset))
    }

    public func setHistoryImported(_ date: Date, account: String) {
        upsertIngest(account: account, column: "history_imported_at", value: date.timeIntervalSince1970)
    }

    public func setHooksInstalled(_ date: Date?, account: String) {
        upsertIngest(account: account, column: "hooks_installed_at", value: date?.timeIntervalSince1970)
    }

    private func upsertIngest(account: String, column: String, value: Any?) {
        queue.sync {
            run("INSERT INTO ingest(account) VALUES(?) ON CONFLICT(account) DO NOTHING", [account])
            run("UPDATE ingest SET \(column) = ? WHERE account = ?", [value, account])
        }
    }

    // MARK: SQLite

    private func exec(_ sql: String) {
        sqlite3_exec(handle, sql, nil, nil, nil)
    }

    private func prepare(_ sql: String, _ params: [Any?]) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        for (i, value) in params.enumerated() {
            let index = Int32(i + 1)
            switch value {
            case let v as String: sqlite3_bind_text(stmt, index, v, -1, SQLITE_TRANSIENT)
            case let v as Double: sqlite3_bind_double(stmt, index, v)
            case let v as Int64: sqlite3_bind_int64(stmt, index, v)
            case let v as Int: sqlite3_bind_int64(stmt, index, Int64(v))
            default: sqlite3_bind_null(stmt, index)
            }
        }
        return stmt
    }

    private func run(_ sql: String, _ params: [Any?]) {
        let stmt = prepare(sql, params)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    private func query<T>(_ sql: String, _ params: [Any?], _ map: (Row) -> T) -> [T] {
        let stmt = prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var result: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(map(Row(stmt: stmt)))
        }
        return result
    }

    struct Row {
        let stmt: OpaquePointer?
        func string(_ i: Int32) -> String? {
            sqlite3_column_text(stmt, i).map { String(cString: $0) }
        }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        func int64(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
    }
}
