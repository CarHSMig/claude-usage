import AppKit
import Combine
import SwiftUI
import UsoClaudeCore

/// O que aparece no ícone do Dock: a conta indicada para uso, com os anéis de sessão e de semana.
private struct DockTileView: View {
    @ObservedObject var store: UsageStore

    /// Tamanho de projeto do ícone; a view é escalada para o tamanho real do tile.
    static let designSize: CGFloat = 128

    var body: some View {
        GeometryReader { geometry in
            tile.scaleEffect(geometry.size.width / Self.designSize, anchor: .topLeading)
        }
    }

    private var tile: some View {
        content
            .padding(.horizontal, 5)
            .frame(width: Self.designSize, height: Self.designSize)
            .background(RoundedRectangle(cornerRadius: 28).fill(Color(red: 0.12, green: 0.12, blue: 0.14)))
    }

    /// Só a conta indicada para uso (a recomendada): nome e os anéis de sessão e de semana.
    /// Sem nenhuma conta com números, mostra um traço.
    @ViewBuilder private var content: some View {
        if let label = store.recommendedLabel, case .ok(let usage, let stale)? = store.states[label] {
            VStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Color(red: 0.30, green: 0.76, blue: 0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                HStack(spacing: 4) {
                    ring(usage.session.utilization)
                    ring(usage.weekly.utilization)
                }
                .opacity(stale ? 0.5 : 1)
            }
        } else {
            Text("–").font(.system(size: 60, weight: .semibold)).foregroundStyle(Color(white: 0.5))
        }
    }

    private func ring(_ utilization: Double) -> some View {
        RingView(utilization: utilization, size: 56, lineWidth: 8, fontSize: 22, showsPercentSign: false)
    }
}

/// Troca o ícone do app no Dock pelos anéis de uso, atualizados a cada mudança dos números.
/// Com o app fechado, o Dock mostra o ícone estático (`AppIcon.icns`).
@MainActor
final class DockIcon {
    private let hosting: NSHostingView<DockTileView>
    private var subscription: AnyCancellable?

    init(store: UsageStore) {
        hosting = NSHostingView(rootView: DockTileView(store: store))
        let tile = NSApp.dockTile
        hosting.frame = NSRect(origin: .zero, size: tile.size)
        tile.contentView = hosting
        // `states` emite no willSet: redesenha na volta do run loop, já com os números novos.
        subscription = Publishers.Merge(store.$states.map { _ in () }, store.$refreshing.map { _ in () })
            .sink { [weak self] in DispatchQueue.main.async { self?.redraw() } }
    }

    private func redraw() {
        let tile = NSApp.dockTile
        hosting.frame = NSRect(origin: .zero, size: tile.size)
        tile.display()
    }
}
