import Foundation
import Testing
@testable import UsoClaudeCore

@Test func dropsPromptAndKeepsAllowedFields() {
    let input = #"{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/p","transcript_path":"/t.jsonl","prompt":"SEGREDO"}"#
    let e = sanitizeHookInput(Data(input.utf8), now: Date(timeIntervalSince1970: 0))!
    #expect(e.event == "UserPromptSubmit" && e.sessionId == "s1" && e.cwd == "/p" && e.transcriptPath == "/t.jsonl")
    #expect(!String(decoding: encodeEventLine(e), as: UTF8.self).contains("SEGREDO"))
}

@Test func keepsToolAndNotificationType() {
    let tool = sanitizeHookInput(Data(#"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"AskUserQuestion","tool_input":{"q":"x"}}"#.utf8), now: .now)!
    #expect(tool.toolName == "AskUserQuestion")
    #expect(!String(decoding: encodeEventLine(tool), as: UTF8.self).contains("tool_input"))
    let note = sanitizeHookInput(Data(#"{"hook_event_name":"Notification","session_id":"s","notification_type":"permission_prompt","message":"m"}"#.utf8), now: .now)!
    #expect(note.notificationType == "permission_prompt")
}

@Test func malformedInputIsNil() {
    #expect(sanitizeHookInput(Data("not json".utf8), now: .now) == nil)
    #expect(sanitizeHookInput(Data(#"{"session_id":"s"}"#.utf8), now: .now) == nil)
}

@Test func lineRoundTrips() {
    let e = HookEvent(ts: Date(timeIntervalSince1970: 1_793_000_000.123), event: "Stop", sessionId: "s",
                      cwd: "/p", transcriptPath: nil, toolName: nil, notificationType: nil)
    let line = encodeEventLine(e)
    #expect(line.last == UInt8(ascii: "\n"))
    let back = decodeEventLine(line.dropLast())!
    #expect(back.event == "Stop" && back.sessionId == "s" && back.cwd == "/p")
    #expect(abs(back.ts.timeIntervalSince(e.ts)) < 0.001)
}
