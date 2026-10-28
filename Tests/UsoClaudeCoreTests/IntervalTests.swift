import Foundation
import Testing
@testable import UsoClaudeCore

private let base = Date(timeIntervalSince1970: 1_793_000_000)
private func t(_ minute: Double) -> Date { base.addingTimeInterval(minute * 60) }
private func ev(_ name: String, _ minute: Double, tool: String? = nil, note: String? = nil) -> HookEvent {
    HookEvent(ts: t(minute), event: name, sessionId: "s", cwd: "/p", transcriptPath: nil,
              toolName: tool, notificationType: note)
}
private func iv(_ start: Double, _ end: Double?) -> AIInterval { AIInterval(start: t(start), end: end.map(t)) }

@Test func promptToStop() {
    #expect(buildIntervals([ev("UserPromptSubmit", 0), ev("PostToolUse", 3), ev("Stop", 5)], now: t(60)) == [iv(0, 5)])
}

@Test func permissionPauseExcluded() {
    let events = [ev("UserPromptSubmit", 0), ev("PreToolUse", 1, tool: "Bash"), ev("PermissionRequest", 2),
                  ev("PostToolUse", 10, tool: "Bash"), ev("Stop", 12)]
    #expect(buildIntervals(events, now: t(60)) == [iv(0, 2), iv(10, 12)])
}

@Test func notificationPermissionPromptPauses() {
    let events = [ev("UserPromptSubmit", 0), ev("Notification", 2, note: "permission_prompt"),
                  ev("PostToolUse", 10), ev("Stop", 12)]
    #expect(buildIntervals(events, now: t(60)) == [iv(0, 2), iv(10, 12)])
}

@Test func permissionRequestThenNotificationPausesOnce() {
    let events = [ev("UserPromptSubmit", 0), ev("PermissionRequest", 2), ev("Notification", 3, note: "permission_prompt"),
                  ev("PostToolUse", 10), ev("Stop", 12)]
    #expect(buildIntervals(events, now: t(60)) == [iv(0, 2), iv(10, 12)])
}

@Test func idleNotificationDoesNotPause() {
    let events = [ev("UserPromptSubmit", 0), ev("Stop", 5), ev("Notification", 6, note: "idle_prompt")]
    #expect(buildIntervals(events, now: t(60)) == [iv(0, 5)])
}

@Test func askUserQuestionPauses() {
    let events = [ev("UserPromptSubmit", 0), ev("PreToolUse", 2, tool: "AskUserQuestion"),
                  ev("PostToolUse", 9, tool: "AskUserQuestion"), ev("Stop", 11)]
    #expect(buildIntervals(events, now: t(60)) == [iv(0, 2), iv(9, 11)])
}

@Test func interruptedTurnClosesAtLastActivity() {
    let events = [ev("UserPromptSubmit", 0), ev("PostToolUse", 4), ev("UserPromptSubmit", 120), ev("Stop", 125)]
    #expect(buildIntervals(events, now: t(200)) == [iv(0, 4), iv(120, 125)])
}

@Test func abandonedOpenTurnClosesAfter30min() {
    #expect(buildIntervals([ev("UserPromptSubmit", 0), ev("PostToolUse", 4)], now: t(40)) == [iv(0, 4)])
}

@Test func activeTurnStaysOpen() {
    #expect(buildIntervals([ev("UserPromptSubmit", 0), ev("PostToolUse", 4)], now: t(10)) == [iv(0, nil)])
}

@Test func sessionEndClosesAtLastActivity() {
    let events = [ev("UserPromptSubmit", 0), ev("PostToolUse", 6), ev("SessionEnd", 50)]
    #expect(buildIntervals(events, now: t(60)) == [iv(0, 6)])
}

@Test func unsortedInputIsSorted() {
    #expect(buildIntervals([ev("Stop", 5), ev("UserPromptSubmit", 0), ev("PostToolUse", 3)], now: t(60)) == [iv(0, 5)])
}

@Test func pausedTurnStopsWithoutResumeEvent() {
    // Permissão negada: a IA pode terminar direto, sem PostToolUse.
    let events = [ev("UserPromptSubmit", 0), ev("PermissionRequest", 2), ev("Stop", 8)]
    #expect(buildIntervals(events, now: t(60)) == [iv(0, 2)])
}

@Test func activityAfterStopStartsInterval() {
    // Ferramentas/agentes que continuam depois do Stop, sem novo prompt, também são trabalho da IA.
    let events = [ev("UserPromptSubmit", 0), ev("Stop", 5), ev("PreToolUse", 6, tool: "Bash"), ev("PostToolUse", 7, tool: "Bash")]
    #expect(buildIntervals(events, now: t(60)) == [iv(0, 5), iv(6, 7)])
}

@Test func stopThenToolsThenStop() {
    let events = [ev("UserPromptSubmit", 0), ev("Stop", 5), ev("SubagentStop", 6), ev("PostToolUse", 7), ev("Stop", 8)]
    #expect(buildIntervals(events, now: t(60)) == [iv(0, 5), iv(6, 8)])
}
