import Foundation
import UsoClaudeCore

// Hook do Claude Code: grava uma linha com o evento e sai.
// Nunca imprime nada (a saída iria para o contexto da IA) e sempre termina com 0.

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--account"), flag + 1 < arguments.count,
   let event = sanitizeHookInput(FileHandle.standardInput.readDataToEndOfFile(), now: Date()) {
    let account = arguments[flag + 1].filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    if !account.isEmpty {
        try? FileManager.default.createDirectory(at: DataPaths.eventsDir, withIntermediateDirectories: true)
        let line = encodeEventLine(event)
        let fd = open(DataPaths.eventsFile(account: account).path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        if fd >= 0 {
            // Uma única escrita com O_APPEND: linhas de hooks simultâneos não se misturam.
            _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            close(fd)
        }
    }
}
exit(0)
