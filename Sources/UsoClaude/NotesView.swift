import AppKit
import SwiftUI
import UsoClaudeCore

/// Aba Notas: uma nota contínua em forma de checklist; os dias anteriores aparecem como snapshots só de leitura.
struct NotesView: View {
    @ObservedObject var notes: NotesStore
    @FocusState private var focused: UUID?
    @State private var keyMonitor: Any?

    private let rowHeight: CGFloat = 20
    private var readOnly: Bool { notes.viewingDay != nil }

    var body: some View {
        let lines = notes.viewedLines
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                navButton("chevron.left", enabled: notes.canGoPrevious) { notes.goPrevious() }
                Spacer()
                Text(title).font(.system(size: 11, weight: .semibold))
                badge
                Spacer()
                navButton("chevron.right", enabled: notes.canGoNext) { notes.goNext() }
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        row(line, index: index)
                    }
                }
            }
            .frame(height: min(CGFloat(max(lines.count, 1)) * rowHeight, 320))

            let counts = noteCounts(lines)
            HStack {
                Text("\(counts.pending) pendente\(counts.pending == 1 ? "" : "s") · \(counts.done) feita\(counts.done == 1 ? "" : "s")")
                Spacer()
                Text(readOnly ? "só leitura" : "Enter = novo item · \"Título:\" · \"- obs\"")
            }
            .font(.system(size: 9))
            .foregroundStyle(Color(white: 0.45))
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .onAppear(perform: installBackspaceMonitor)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    private var title: String {
        let date: Date
        if let day = notes.viewingDay, let parsed = Self.dayParser.date(from: day) { date = parsed } else { date = Date() }
        return ReportPeriod.day(date).title(calendar: notes.calendar)
    }

    private var badge: some View {
        Text(readOnly ? "snapshot" : "hoje")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(readOnly ? Color(white: 0.7) : Color(red: 0.05, green: 0.16, blue: 0.09))
            .padding(.horizontal, 6)
            .background(Capsule().fill(readOnly ? Color(white: 0.25) : Color(red: 0.30, green: 0.76, blue: 0.48)))
    }

    @ViewBuilder private func row(_ line: NoteLine, index: Int) -> some View {
        let kind = noteLineKind(line.text)
        HStack(spacing: 7) {
            switch kind {
            case .item:
                Button { if !readOnly { edit(index) { $0.done.toggle() } } } label: {
                    Image(systemName: line.done ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12))
                        .foregroundStyle(line.done ? Color(red: 0.30, green: 0.76, blue: 0.48) : Color(white: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(readOnly)
            case .remark, .heading:
                Color.clear.frame(width: 12, height: 1)
            }

            if readOnly {
                Text(line.text).lineLimit(1).modifier(LineStyle(kind: kind, done: line.done))
                Spacer(minLength: 0)
            } else {
                TextField(index == 0 && notes.lines.count == 1 ? "Escreva uma tarefa e tecle Enter" : "",
                          text: Binding(get: { line.text }, set: { text in edit(index) { $0.text = text } }))
                    .textFieldStyle(.plain)
                    .modifier(LineStyle(kind: kind, done: line.done))
                    .focused($focused, equals: line.id)
                    .onSubmit { insertLine(after: index) }
                    .onKeyPress(.upArrow) { moveFocus(from: index, by: -1) }
                    .onKeyPress(.downArrow) { moveFocus(from: index, by: 1) }
            }
        }
        .frame(height: rowHeight)
    }

    // MARK: Edição

    private func edit(_ index: Int, _ change: (inout NoteLine) -> Void) {
        var lines = notes.lines
        guard lines.indices.contains(index) else { return }
        change(&lines[index])
        notes.update(lines)
    }

    private func insertLine(after index: Int) {
        var lines = notes.lines
        let new = NoteLine()
        lines.insert(new, at: min(index + 1, lines.count))
        notes.update(lines)
        focused = new.id
    }

    /// O campo em edição entrega o Backspace ao editor de texto do AppKit (`deleteBackward:`) antes do
    /// `onKeyPress`, então a tecla é interceptada aqui, antes de chegar ao campo.
    private func installBackspaceMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard event.keyCode == 51, modifiers.isEmpty, !readOnly,
                  let id = focused, let index = notes.lines.firstIndex(where: { $0.id == id }) else { return event }
            return removeIfEmpty(index) ? nil : event
        }
    }

    /// Backspace numa linha vazia apaga a linha e volta para a anterior, com o cursor no fim do texto.
    private func removeIfEmpty(_ index: Int) -> Bool {
        var lines = notes.lines
        guard lines.count > 1, lines.indices.contains(index), lines[index].text.isEmpty else { return false }
        lines.remove(at: index)
        notes.update(lines)
        focused = lines[max(index - 1, 0)].id
        // Ao ganhar foco o NSTextField seleciona tudo; sem isso o próximo Backspace apagaria a linha anterior inteira.
        DispatchQueue.main.async {
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        }
        return true
    }

    private func moveFocus(from index: Int, by step: Int) -> KeyPress.Result {
        let target = index + step
        guard notes.lines.indices.contains(target) else { return .ignored }
        focused = notes.lines[target].id
        return .handled
    }

    private func navButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 18)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.18)))
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

private struct LineStyle: ViewModifier {
    let kind: NoteLineKind
    let done: Bool

    func body(content: Content) -> some View {
        switch kind {
        case .heading:
            content.font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(white: 0.82))
        case .remark:
            content.italic().foregroundStyle(Color(white: 0.6))
        case .item:
            content.strikethrough(done).foregroundStyle(done ? Color(white: 0.48) : Color(white: 0.92))
        }
    }
}
