import AppKit
import SwiftUI
import UsoClaudeCore

struct UsageView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var pin: PinState
    @ObservedObject var hours: HoursStore
    let notes: NotesStore
    let onTogglePin: () -> Void
    let onActivateHooks: () -> Void

    @AppStorage("hoursDrawerOpen") private var drawerOpen = false
    @AppStorage("drawerTab") private var tab = "hours"

    var body: some View {
        VStack(spacing: 0) {
            limits
            if drawerOpen {
                Rectangle().fill(Color(white: 0.22)).frame(height: 1).padding(.horizontal, 12).padding(.bottom, 8)
                tabs
                if tab == "notes" {
                    NotesView(notes: notes)
                } else {
                    HoursDrawer(hours: hours, onActivateHooks: onActivateHooks)
                }
            }
        }
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.12, green: 0.12, blue: 0.14)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            tabButton("Horas", id: "hours")
            tabButton("Notas", id: "notes")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func tabButton(_ title: String, id: String) -> some View {
        Button { tab = id } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tab == id ? Color(red: 0.05, green: 0.16, blue: 0.09) : Color(white: 0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(Capsule().fill(tab == id ? Color(red: 0.30, green: 0.76, blue: 0.48) : Color(white: 0.16)))
        }
        .buttonStyle(.plain)
    }

    private var limits: some View {
        ZStack(alignment: .topTrailing) {
            // Camada de fundo: arrasta a janela, e um clique sem arrastar atualiza os números.
            // Cada quadro de conta tem a sua própria camada igual, que atualiza só aquela conta.
            DragArea { Task { await store.refreshIfIdle() } }

            VStack(spacing: 8) {
                Text("Uso Claude")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    HStack(spacing: 8) {
                        ForEach(store.accounts) { account in
                            AccountColumn(label: account.label,
                                          state: store.states[account.label] ?? .loading,
                                          isRecommended: store.recommendedLabel == account.label,
                                          isRefreshing: store.refreshing.contains(account.label),
                                          now: context.date,
                                          onRefresh: { Task { await store.refreshIfIdle(account: account.label) } })
                        }
                    }
                }
            }
            .padding(12)

            HStack(spacing: 8) {
                Button { drawerOpen.toggle() } label: {
                    Text(drawerOpen ? "▴ Horas · Notas" : "▾ Horas · Notas")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(white: 0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.22)))
                }
                .buttonStyle(.plain)
                .help("Horas de IA e notas do dia")
                Button(action: onTogglePin) {
                    Text("📌")
                        .font(.system(size: 12))
                        .opacity(pin.isPinned ? 1 : 0.35)
                }
                .buttonStyle(.plain)
                .help(pin.isPinned ? "Desafixar" : "Fixar na frente")
            }
            .padding(10)
        }
    }
}

private struct AccountColumn: View {
    let label: String
    let state: AccountState
    let isRecommended: Bool
    let isRefreshing: Bool
    let now: Date
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .opacity(isRefreshing ? 0.55 : 1)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.15, green: 0.15, blue: 0.18)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.30, green: 0.76, blue: 0.48), lineWidth: isRecommended ? 1 : 0)
        )
        .overlay(DragArea(onClick: onRefresh))
        .help("Clique para atualizar \(label)")
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        case .unavailable:
            Spacer()
            Text("sem conexão")
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.7))
            Spacer()
        case .loginExpired:
            Spacer()
            Text("abra o Claude Code nessa conta")
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
            Spacer()
        case .ok(let usage, let stale):
            Group {
                RingView(utilization: usage.session.utilization)
                caption("sessão · \(sessionResetText(usage.session.resetsAt, now: now))")
                RingView(utilization: usage.weekly.utilization)
                caption("semana · \(weeklyResetText(usage.weekly.resetsAt))")
            }
            .opacity(stale ? 0.5 : 1)
            // Linha sempre reservada, para a coluna não mudar de altura ao ficar sem conexão.
            caption("sem conexão").opacity(stale ? 1 : 0)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(Color(white: 0.55))
    }
}

/// NSView de fundo que arrasta a janela; se o mouse soltar sem mover, conta como clique.
private struct DragArea: NSViewRepresentable {
    let onClick: () -> Void

    func makeNSView(context: Context) -> DragNSView {
        let view = DragNSView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: DragNSView, context: Context) {
        view.onClick = onClick
    }

    final class DragNSView: NSView {
        var onClick: (() -> Void)?

        // Sem isso, com o app inativo o primeiro clique só ativaria a janela.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let before = window.frame.origin
            window.performDrag(with: event)
            if window.frame.origin == before { onClick?() }
        }
    }
}
