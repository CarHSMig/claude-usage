// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "UsoClaude",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "UsoClaudeCore"),
        .executableTarget(name: "UsoClaude", dependencies: ["UsoClaudeCore"]),
        .executableTarget(name: "UsoClaudeHook", dependencies: ["UsoClaudeCore"]),
        .testTarget(name: "UsoClaudeCoreTests", dependencies: ["UsoClaudeCore"]),
    ]
)
