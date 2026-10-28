import Foundation

/// Nome do projeto de uma pasta. Worktrees do mesmo repositório viram o nome do repositório principal;
/// pastas que já não existem tentam casar com um projeto conhecido pelo prefixo ("proteo-feat-x" → "proteo").
public func projectName(forCwd cwd: String, gitCommonDir: String?, knownProjects: [String]) -> String {
    if let gitCommonDir {
        let url = URL(fileURLWithPath: gitCommonDir)
        let root = url.lastPathComponent == ".git" ? url.deletingLastPathComponent() : url
        let name = root.lastPathComponent
        return name.hasSuffix(".git") ? String(name.dropLast(4)) : name
    }
    // Pasta sem git (ex.: worktree já apagada): reconhece os padrões de worktree pelo caminho.
    let parts = URL(fileURLWithPath: cwd).pathComponents
    if let w = parts.lastIndex(of: "worktrees"), w > 0 {
        // <repo>/.claude/worktrees/<nome> → <repo>
        if parts[w - 1] == ".claude", w >= 2 { return parts[w - 2] }
        // ~/.herdr/worktrees/<repo>/<nome> → <repo>
        if w + 2 < parts.count { return parts[w + 1] }
    }
    let base = URL(fileURLWithPath: cwd).lastPathComponent
    let prefixMatch = knownProjects
        .filter { base.hasPrefix($0 + "-") }
        .max(by: { $0.count < $1.count })
    return prefixMatch ?? base
}

/// Resolve (e guarda) o projeto de uma pasta, consultando o git se a pasta ainda existir.
@discardableResult
public func resolveProject(cwd: String, db: HoursDB, knownProjects: [String]) async -> String {
    if let cached = db.project(forCwd: cwd) { return cached }
    var gitCommonDir: String?
    if FileManager.default.fileExists(atPath: cwd),
       let data = await runProcess("/usr/bin/git", ["-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                   timeout: 2) {
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        gitCommonDir = path.isEmpty ? nil : path
    }
    let project = projectName(forCwd: cwd, gitCommonDir: gitCommonDir, knownProjects: knownProjects)
    db.setProject(project, forCwd: cwd)
    return project
}

/// Resolve todas as pastas ainda sem projeto. As que existem vão primeiro, para que seus nomes
/// sirvam de prefixo conhecido para worktrees já apagadas.
public func resolvePendingProjects(db: HoursDB) async {
    let pending = db.unresolvedCwds()
    let existing = pending.filter { FileManager.default.fileExists(atPath: $0) }
    let missing = pending.filter { !FileManager.default.fileExists(atPath: $0) }
    for cwd in existing {
        await resolveProject(cwd: cwd, db: db, knownProjects: [])
    }
    let known = db.knownProjects()
    for cwd in missing {
        await resolveProject(cwd: cwd, db: db, knownProjects: known)
    }
}
