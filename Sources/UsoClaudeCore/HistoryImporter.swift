import Foundation

private struct TranscriptLine: Decodable {
    let type: String?
    let subtype: String?
    let durationMs: Double?
    let timestamp: String?
    let sessionId: String?
    let cwd: String?
    let isSidechain: Bool?
    let aiTitle: String?
    let uuid: String?
}

private let turnDurationMarker = Data("turn_duration".utf8)
private let aiTitleMarker = Data("ai-title".utf8)

/// Importa, uma única vez por conta, o tempo exato (`turn_duration`) que ainda existe nos transcripts.
public struct HistoryImporter: Sendable {
    private let db: HoursDB

    public init(db: HoursDB) {
        self.db = db
    }

    /// `force` reimporta mesmo se já houve importação (usado ao ativar os hooks, com o corte no momento
    /// da ativação). É seguro repetir: os intervalos importados de cada sessão são substituídos, não somados.
    public func importHistory(account: Account, before cutoff: Date, force: Bool = false) async {
        guard force || db.ingestState(account: account.label).historyImportedAt == nil else { return }
        let projectsDir = URL(fileURLWithPath: account.directory).appendingPathComponent("projects")
        let folders = (try? FileManager.default.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        // Sessões retomadas ou bifurcadas copiam turnos antigos para outro arquivo: cada turno conta uma vez.
        var seenTurns = Set<String>()
        // Turnos de sessões que os hooks já registravam não são importados (contariam duas vezes).
        let hookedSince = db.firstHookEventTimes(account: account.label)
        for folder in folders.sorted(by: { $0.path < $1.path }) {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files.sorted(by: { $0.path < $1.path }) where file.pathExtension == "jsonl" {
                importFile(file, account: account.label, cutoff: cutoff, hookedSince: hookedSince, seenTurns: &seenTurns)
                await Task.yield()
            }
        }
        await resolvePendingProjects(db: db)
        db.setHistoryImported(Date(), account: account.label)
    }

    private func importFile(_ file: URL, account: String, cutoff: Date, hookedSince: [String: Date],
                            seenTurns: inout Set<String>) {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return }
        var bySession: [String: (cwd: String?, intervals: [AIInterval])] = [:]
        let decoder = JSONDecoder()
        for line in data.split(separator: UInt8(ascii: "\n")) {
            // Só decodifica as linhas que interessam; as demais (mensagens) podem ser enormes.
            let isDuration = line.range(of: turnDurationMarker) != nil
            guard isDuration || line.range(of: aiTitleMarker) != nil,
                  let entry = try? decoder.decode(TranscriptLine.self, from: Data(line)),
                  let session = entry.sessionId else { continue }
            if entry.type == "ai-title", let title = entry.aiTitle {
                db.setSessionTitle(title, session: session, account: account)
            } else if entry.type == "system", entry.subtype == "turn_duration", entry.isSidechain != true,
                      let ms = entry.durationMs, let stamp = entry.timestamp.flatMap(parseISODate), stamp < cutoff,
                      hookedSince[session].map({ stamp < $0 }) ?? true,
                      seenTurns.insert(entry.uuid ?? "\(entry.timestamp ?? "")|\(ms)").inserted {
                var current = bySession[session] ?? (cwd: entry.cwd, intervals: [])
                current.intervals.append(AIInterval(start: stamp.addingTimeInterval(-ms / 1000), end: stamp))
                bySession[session] = current
            }
        }
        for (session, value) in bySession {
            db.replaceIntervals(session: session, account: account, cwd: value.cwd, value.intervals, source: "import")
        }
    }
}

/// Título mais recente (`ai-title`) gravado no transcript de uma sessão.
public func readSessionTitle(transcriptPath: String) -> String? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: transcriptPath), options: .mappedIfSafe) else { return nil }
    var title: String?
    for line in data.split(separator: UInt8(ascii: "\n")) where line.range(of: aiTitleMarker) != nil {
        if let entry = try? JSONDecoder().decode(TranscriptLine.self, from: Data(line)), entry.type == "ai-title" {
            title = entry.aiTitle ?? title
        }
    }
    return title
}
