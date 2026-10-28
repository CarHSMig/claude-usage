import Foundation

/// Lê, a partir do último ponto lido, as linhas que o hook acrescentou em `events/<conta>.jsonl`
/// e recalcula os intervalos das sessões afetadas.
public struct EventIngestor: Sendable {
    private let db: HoursDB
    private let eventsDir: URL

    public init(db: HoursDB, eventsDir: URL) {
        self.db = db
        self.eventsDir = eventsDir
    }

    /// Retorna as sessões que receberam eventos novos.
    @discardableResult
    public func ingest(account: String, now: Date) -> Set<String> {
        let file = eventsDir.appendingPathComponent("\(account).jsonl")
        var touched = Set<String>()
        if let handle = try? FileHandle(forReadingFrom: file) {
            defer { try? handle.close() }
            let state = db.ingestState(account: account)
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            let fileID = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
            let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
            // Arquivo recriado ou truncado: lê de novo desde o começo (eventos repetidos não mudam os intervalos).
            let offset = (state.fileID != nil && state.fileID != fileID) || size < state.offset ? 0 : state.offset
            try? handle.seek(toOffset: offset)
            let data = (try? handle.readToEnd()) ?? Data()
            // Só consome até a última quebra de linha: uma linha pela metade fica para a próxima leitura.
            if let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) {
                let complete = data[data.startIndex...lastNewline]
                let events = complete.split(separator: UInt8(ascii: "\n")).compactMap { decodeEventLine($0) }
                db.commitIngest(events, account: account, offset: offset + UInt64(complete.count), fileID: fileID)
                touched = Set(events.map(\.sessionId))
            }
        }
        // Sessões com intervalo aberto também são recalculadas, para o tempo de abandono valer.
        rebuild(touched.union(db.sessionsWithOpenIntervals(account: account)), account: account, now: now)
        return touched
    }

    /// Recalcula todas as sessões registradas pelos hooks (ex.: depois de mudar as regras de contagem).
    public func rebuildAll(account: String, now: Date) {
        rebuild(Set(db.hookSessions(account: account)), account: account, now: now)
    }

    private func rebuild(_ sessions: Set<String>, account: String, now: Date) {
        for session in sessions {
            let events = db.events(session: session)
            db.replaceIntervals(session: session, account: account, cwd: events.lazy.compactMap(\.cwd).first,
                                buildIntervals(events, now: now), source: "hook")
        }
    }
}
