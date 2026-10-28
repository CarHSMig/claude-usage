import Foundation

/// Um trecho contínuo de IA executando. `end == nil` = ainda em andamento.
public struct AIInterval: Sendable, Equatable {
    public let start: Date
    public var end: Date?

    public init(start: Date, end: Date?) {
        self.start = start
        self.end = end
    }
}

/// Ferramentas que esperam o usuário responder: o tempo até a resposta não é da IA.
private let waitingTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]
private let activityEvents: Set<String> = ["PreToolUse", "PostToolUse", "PostToolUseFailure", "SubagentStart", "SubagentStop"]
private let abandonTimeout: TimeInterval = 30 * 60

private func isPause(_ e: HookEvent) -> Bool {
    switch e.event {
    case "PermissionRequest": return true
    case "Notification": return e.notificationType == "permission_prompt"
    case "PreToolUse": return e.toolName.map(waitingTools.contains) ?? false
    default: return false
    }
}

/// Transforma os eventos de UMA sessão nos intervalos em que a IA estava executando.
public func buildIntervals(_ events: [HookEvent], now: Date) -> [AIInterval] {
    enum State {
        case idle
        case paused
        case running(start: Date, lastActivity: Date)
    }
    var state = State.idle
    var result: [AIInterval] = []

    for e in events.sorted(by: { $0.ts < $1.ts }) {
        if isPause(e) {
            if case .running(let start, _) = state {
                result.append(AIInterval(start: start, end: e.ts))
                state = .paused
            }
            continue
        }
        switch e.event {
        case "UserPromptSubmit":
            // Turno anterior sem Stop (interrompido com Esc): termina na última atividade.
            if case .running(let start, let last) = state {
                result.append(AIInterval(start: start, end: last))
            }
            state = .running(start: e.ts, lastActivity: e.ts)
        case "Stop":
            if case .running(let start, _) = state {
                result.append(AIInterval(start: start, end: e.ts))
            }
            state = .idle
        case "SessionEnd":
            if case .running(let start, let last) = state {
                result.append(AIInterval(start: start, end: last))
            }
            state = .idle
        case let name where activityEvents.contains(name):
            switch state {
            case .running(let start, _): state = .running(start: start, lastActivity: e.ts)
            // Pausado ou ocioso: atividade sem novo prompt (agentes/ferramentas depois do Stop,
            // continuação automática) também é trabalho da IA.
            case .paused, .idle: state = .running(start: e.ts, lastActivity: e.ts)
            }
        default:
            break
        }
    }

    if case .running(let start, let last) = state {
        let abandoned = now.timeIntervalSince(last) > abandonTimeout
        result.append(AIInterval(start: start, end: abandoned ? last : nil))
    }
    return result
}
