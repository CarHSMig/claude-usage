# Uso Claude — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS floating window that shows the session (5h) and weekly usage limits of the user's two Claude Code accounts side by side, and highlights which account to use.

**Architecture:** SwiftPM package with a testable library `UsoClaudeCore` (account config, Keychain reading via `/usr/bin/security`, usage API client, parsing, recommendation, formatting, refresh store) and an executable `UsoClaude` (AppKit `NSPanel` hosting SwiftUI, menu bar item). A shell script assembles `build/Uso Claude.app` and optionally installs it to `/Applications`.

**Tech Stack:** Swift 6.1 (Command Line Tools only, no Xcode), SwiftUI + AppKit, Swift Testing, URLSession.

**Spec:** `docs/superpowers/specs/2026-10-26-usage-widget-design.md`

## Global Constraints

- `Package.swift`: `// swift-tools-version: 6.1`, `platforms: [.macOS(.v14)]` (required for Swift Testing to compile).
- Tests use `import Testing` (`@Test`, `#expect`); XCTest is unavailable.
- Read-only: never refresh tokens, never write to the Keychain, never log/print/persist a token.
- Accounts are fixed in code: `("claude", "~/.claude")`, `("proteo", "~/.claude-proteo")`. Ignore `Claude Code-credentials-a4ed6c15`.
- Keychain service: `"Claude Code-credentials"` for `~/.claude`; otherwise `"Claude Code-credentials-" + first 8 lowercase hex of SHA-256(absolute dir path)`.
- Endpoint: `GET https://api.anthropic.com/api/oauth/usage`, headers `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`.
- Colors: green < 50, yellow 50–80, red > 80 (utilization 0–100).
- Refresh every 90 s; click-to-refresh debounced to 10 s; token re-read from Keychain every cycle.
- UI copy in Portuguese: "abra o Claude Code nessa conta", "sem conexão", menu items "Mostrar/Ocultar janela", "Atualizar agora", "Sair".
- App is `LSUIElement` (no Dock icon); does not register itself as a login item.
- The project directory is not a git repo; skip commit steps unless the user initializes one.

## Review Focus

1. `resets_at` with fractional seconds and offset (`2026-10-29T10:00:00.083054+00:00`) — must parse; plain `ISO8601DateFormatter` without `.withFractionalSeconds` fails silently. Test in Task 2.
2. `resets_at: null` (session idle) — show "—", not crash or "em 0min". Test in Task 2.
3. Both accounts at 100% weekly — no account recommended (no green outline). Test in Task 2.
4. Keychain item missing or JSON without `claudeAiOauth` — account shows expired-login state, other account still works. Test in Task 3.
5. Network failure after a successful fetch — keep last numbers, flag `stale`. Test in Task 3.

---

### Task 1: Package scaffold + account / Keychain service derivation

**Files:**
- Create: `Package.swift`, `Sources/UsoClaudeCore/Account.swift`, `Sources/UsoClaude/main.swift` (placeholder `print("UsoClaude")` until Task 4), `Tests/UsoClaudeCoreTests/AccountTests.swift`, `.gitignore` (`.build/`, `build/`, `.superpowers/`)

**Interfaces:**
- Produces:
  - `public struct Account: Sendable, Identifiable, Hashable { public let label: String; public let directory: String /* absolute, expanded */; public var id: String { label } }`
  - `public static let all: [Account]` on `Account` (expands `~` with `NSHomeDirectory()`)
  - `public func keychainService(for directory: String, home: String) -> String`

- [ ] **Step 1: Write failing tests**

```swift
@Test func defaultDirUsesPlainService() {
  #expect(keychainService(for: "/Users/u/.claude", home: "/Users/u") == "Claude Code-credentials")
}
@Test func customDirUsesHashSuffix() {
  #expect(keychainService(for: "/Users/exemplo/.claude-proteo",
                          home: "/Users/exemplo") == "Claude Code-credentials-99f7bf74")
}
@Test func accountsAreTheTwoConfigured() {
  #expect(Account.all.map(\.label) == ["claude", "proteo"])
}
```

- [ ] **Step 2:** `swift test` → FAIL (symbols missing).
- [ ] **Step 3:** Implement with `CryptoKit.SHA256` over the UTF-8 path.
- [ ] **Step 4:** `swift test` → all pass.

---

### Task 2: Usage model, parsing, recommendation, formatting

**Files:**
- Create: `Sources/UsoClaudeCore/Usage.swift`, `Sources/UsoClaudeCore/Recommendation.swift`, `Sources/UsoClaudeCore/Formatting.swift`, `Tests/UsoClaudeCoreTests/UsageTests.swift`

**Interfaces:**
- Produces:
  - `public struct Window: Sendable, Equatable { public let utilization: Double; public let resetsAt: Date? }`
  - `public struct Usage: Sendable, Equatable { public let session: Window; public let weekly: Window }`
  - `public func parseUsage(_ data: Data) throws -> Usage` (reads `five_hour`, `seven_day`; ignores other keys)
  - `public enum Level { case green, yellow, red }`; `public func level(for utilization: Double) -> Level`
  - `public func recommended(_ usages: [String: Usage]) -> String?` (key = account label)
  - `public func sessionResetText(_ resetsAt: Date?, now: Date) -> String` → `"em 2h40"`, `"em 35min"`, `"—"` for nil
  - `public func weeklyResetText(_ resetsAt: Date?, calendar: Calendar) -> String` → `"dom 22:00"` (pt_BR short weekday, lowercase, no dot), `"—"` for nil

- [ ] **Step 1: Write failing tests** — use the real fixture captured on 2026-10-26:

```swift
let fixture = #"{"five_hour":{"utilization":54.0,"resets_at":"2026-10-27T04:50:00.499950+00:00"},"seven_day":{"utilization":30.0,"resets_at":"2026-11-02T01:00:00.499973+00:00"},"tangelo":null}"#
@Test func parsesFractionalSecondsAndOffset() throws {
  let u = try parseUsage(Data(fixture.utf8))
  #expect(u.session.utilization == 54 && u.weekly.utilization == 30)
  #expect(u.session.resetsAt == ISO8601DateFormatter().date(from: "2026-10-27T04:50:00Z")!.addingTimeInterval(0.49995))
}
@Test func nullResetsAtIsNil() throws { /* five_hour.resets_at null → session.resetsAt == nil */ }
@Test func levels() { #expect(level(for: 49.9) == .green); #expect(level(for: 50) == .yellow); #expect(level(for: 80) == .yellow); #expect(level(for: 80.1) == .red) }
@Test func recommendsLowerWeekly() { /* claude weekly 100/session 0, proteo 30/54 → "proteo" */ }
@Test func tieBreaksOnSession() { /* weekly 40 vs 43, session 70 vs 10 → the one with session 10 */ }
@Test func neverRecommendsExhaustedWhenOtherHasRoom() { /* a: weekly 10 session 100; b: weekly 60 session 20 → "b" */ }
@Test func noRecommendationWhenBothExhausted() { /* both weekly 100 → nil */ }
@Test func sessionResetText() { /* now+2h40m → "em 2h40"; now+35m → "em 35min"; nil → "—" */ }
@Test func weeklyResetText() { /* 2026-11-02T01:00Z with TimeZone "America/Sao_Paulo" → "dom 22:00" */ }
```

Recommendation rule (spec): drop accounts with any window ≥ 100 if at least one other account has both < 100; if none remain → `nil`; among remaining, lowest weekly; if the two lowest differ by < 5 points, pick lower session.

- [ ] **Step 2:** `swift test` → FAIL.
- [ ] **Step 3:** Implement. Date parsing: `ISO8601DateFormatter` with `[.withInternetDateTime, .withFractionalSeconds]`, falling back to without fractional seconds.
- [ ] **Step 4:** `swift test` → all pass.

---

### Task 3: Credentials, API client, refresh store

**Files:**
- Create: `Sources/UsoClaudeCore/Credentials.swift`, `Sources/UsoClaudeCore/UsageClient.swift`, `Sources/UsoClaudeCore/UsageStore.swift`, `Tests/UsoClaudeCoreTests/StoreTests.swift`

**Interfaces:**
- Consumes: `Account`, `keychainService`, `Usage`, `parseUsage`.
- Produces:
  - `public struct Credential: Sendable { public let accessToken: String; public let expiresAt: Date }`
  - `public func parseCredential(_ data: Data) -> Credential?` (`claudeAiOauth.accessToken`, `expiresAt` ms epoch)
  - `public protocol UsageSource: Sendable { func credential(for: Account) async -> Credential?; func fetch(token: String) async throws -> Usage }` — `UsageClient.unauthorized` error for HTTP 401.
  - `public struct LiveUsageSource: UsageSource` — runs `/usr/bin/security find-generic-password -s <service> -w` via `Process` (stdout captured, stderr discarded), `URLSession` for fetch, 15 s timeout.
  - `public enum AccountState: Equatable { case loading; case ok(Usage, stale: Bool); case loginExpired }`
  - `@MainActor public final class UsageStore: ObservableObject { @Published public private(set) var states: [String: AccountState]; public var recommendedLabel: String? { get }; public init(accounts: [Account], source: UsageSource); public func refresh() async; public func refreshIfIdle(now: Date) async /* 10 s debounce */; public func start() /* 90 s timer */ }`

- [ ] **Step 1: Write failing tests** with a fake `UsageSource`:

```swift
@Test func expiredCredentialSkipsFetch() async { /* expiresAt in past → .loginExpired, fetch never called */ }
@Test func missingCredentialIsLoginExpired() async { /* credential nil → .loginExpired; other account .ok */ }
@Test func unauthorizedIsLoginExpired() async { /* fetch throws .unauthorized → .loginExpired */ }
@Test func networkErrorKeepsLastValueAsStale() async { /* 1st ok, 2nd throws URLError → .ok(sameUsage, stale: true) */ }
@Test func networkErrorWithoutPreviousValueStaysLoading() async { /* first fetch throws URLError → .loading */ }
@Test func debounceSkipsWithin10s() async { /* two refreshIfIdle calls 5 s apart → fetch called once */ }
@Test func parseCredentialWithoutOauthKeyIsNil() { #expect(parseCredential(Data(#"{"mcpOAuth":{}}"#.utf8)) == nil) }
```

- [ ] **Step 2:** `swift test` → FAIL.
- [ ] **Step 3:** Implement; accounts fetched concurrently (`withTaskGroup`).
- [ ] **Step 4:** `swift test` → all pass.
- [ ] **Step 5: Live smoke check** — temporary `main.swift` prints only `label: session% / weekly%` per account using `LiveUsageSource` (no tokens). Run `swift run UsoClaude`; expect two lines with numbers. Revert to placeholder after.

---

### Task 4: Window, rings, pin, menu bar

**Files:**
- Create: `Sources/UsoClaude/main.swift` (NSApplication bootstrap, `.accessory` activation policy), `Sources/UsoClaude/AppDelegate.swift`, `Sources/UsoClaude/FloatingPanel.swift`, `Sources/UsoClaude/UsageView.swift`, `Sources/UsoClaude/RingView.swift`

**Interfaces:**
- Consumes: `UsageStore`, `AccountState`, `level(for:)`, `sessionResetText`, `weeklyResetText`, `Account.all`, `LiveUsageSource`.

Requirements (from spec):
- `FloatingPanel: NSPanel` — `.borderless, .nonactivatingPanel`, transparent background, rounded dark content (~300×200 pt), `isMovableByWindowBackground = true`.
- Pin button 📌 top-right: on → `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`; off → `.normal`, `[]`. Pin state and frame origin persisted in `UserDefaults` (`pinned`, `windowOrigin`); restored at launch.
- `UsageView`: two columns (account order of `Account.all`), each: label, session ring (% + `sessionResetText`), weekly ring (% + `weeklyResetText`). Ring color from `level`. Recommended column gets 1 pt green outline. `.loginExpired` → column shows "abra o Claude Code nessa conta". `stale` → rings at 50% opacity plus "sem conexão". `.loading` → `ProgressView`.
- Clicking the window background calls `store.refreshIfIdle(now:)`.
- `NSStatusItem` (SF Symbol `gauge.with.dots.needle.33percent`) with menu: "Mostrar/Ocultar janela", "Atualizar agora", separator, "Sair".

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** `swift build` → succeeds with no errors.
- [ ] **Step 3: Manual verification** — `swift run UsoClaude`; confirm: window appears with real numbers for both accounts, proteo outlined; drag works; pin keeps it above a focused Finder window and across Spaces; unpin lets it go behind; quit + relaunch restores position and pin; menu items work; no Dock icon.

---

### Task 5: App bundle, install, README

**Files:**
- Create: `scripts/build-app.sh`, `Resources/Info.plist`, `README.md`

Requirements:
- `scripts/build-app.sh [--install]`: `swift build -c release`; assemble `build/Uso Claude.app/Contents/{MacOS/UsoClaude, Info.plist}`; `codesign --force -s - "build/Uso Claude.app"`; with `--install`, replace `/Applications/Uso Claude.app`.
- `Info.plist`: `CFBundleIdentifier` `com.carlosmigon.usoclaude`, `CFBundleName` `Uso Claude`, `CFBundleExecutable` `UsoClaude`, `LSUIElement` `true`, `LSMinimumSystemVersion` `14.0`.
- `README.md` (Portuguese): what it does, build/install commands, how to enable "abrir ao ligar" via Ajustes do Sistema › Geral › Itens de Início › "+", note that the endpoint is unofficial and that an expired login is fixed by opening Claude Code in that account.

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** `bash scripts/build-app.sh` → `build/Uso Claude.app` exists; `codesign -v "build/Uso Claude.app"` exits 0.
- [ ] **Step 3:** `open "build/Uso Claude.app"` → window appears, no Dock icon, numbers load.
- [ ] **Step 4:** `bash scripts/build-app.sh --install` → `/Applications/Uso Claude.app` exists and launches.
