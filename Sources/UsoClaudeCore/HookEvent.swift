import Foundation

/// Um evento de hook do Claude Code, já sem nenhum conteúdo de conversa.
public struct HookEvent: Codable, Sendable, Equatable {
    public let ts: Date
    public let event: String
    public let sessionId: String
    public let cwd: String?
    public let transcriptPath: String?
    public let toolName: String?
    public let notificationType: String?

    public init(ts: Date, event: String, sessionId: String, cwd: String?, transcriptPath: String?,
                toolName: String?, notificationType: String?) {
        self.ts = ts
        self.event = event
        self.sessionId = sessionId
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.toolName = toolName
        self.notificationType = notificationType
    }

    enum CodingKeys: String, CodingKey {
        case ts, event, cwd
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case toolName = "tool_name"
        case notificationType = "notification_type"
    }
}

/// Entrada que o Claude Code manda no stdin do hook. Só os campos permitidos são decodificados;
/// o resto (prompt, tool_input, mensagens) é ignorado e nunca chega ao disco.
private struct RawHookInput: Decodable {
    let hook_event_name: String
    let session_id: String
    let cwd: String?
    let transcript_path: String?
    let tool_name: String?
    let notification_type: String?
}

public func sanitizeHookInput(_ stdin: Data, now: Date) -> HookEvent? {
    guard let raw = try? JSONDecoder().decode(RawHookInput.self, from: stdin) else { return nil }
    return HookEvent(ts: now, event: raw.hook_event_name, sessionId: raw.session_id, cwd: raw.cwd,
                     transcriptPath: raw.transcript_path, toolName: raw.tool_name,
                     notificationType: raw.notification_type)
}

private func eventDateFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}

public func encodeEventLine(_ e: HookEvent) -> Data {
    let encoder = JSONEncoder()
    let formatter = eventDateFormatter()
    encoder.dateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(formatter.string(from: date))
    }
    encoder.outputFormatting = [.withoutEscapingSlashes]
    var data = (try? encoder.encode(e)) ?? Data()
    data.append(UInt8(ascii: "\n"))
    return data
}

public func decodeEventLine<D: DataProtocol>(_ line: D) -> HookEvent? {
    let decoder = JSONDecoder()
    let formatter = eventDateFormatter()
    decoder.dateDecodingStrategy = .custom { decoder in
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let date = formatter.date(from: string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "data inválida"))
        }
        return date
    }
    return try? decoder.decode(HookEvent.self, from: Data(line))
}

public enum DataPaths {
    public static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UsoClaude", isDirectory: true)
    }

    public static var eventsDir: URL { root.appendingPathComponent("events", isDirectory: true) }

    public static func eventsFile(account: String) -> URL {
        eventsDir.appendingPathComponent("\(account).jsonl")
    }

    public static var database: URL { root.appendingPathComponent("usage.sqlite") }
}
