import CoreGraphics

/// Posição salva ajustada para a janela inteira caber na tela onde está a origem.
/// Retorna `nil` se a origem não cai em nenhuma tela (ex.: monitor desconectado).
public func clampedOrigin(_ origin: CGPoint, size: CGSize, screens: [CGRect]) -> CGPoint? {
    guard let screen = screens.first(where: { $0.contains(origin) }) else { return nil }
    let x = min(max(origin.x, screen.minX), screen.maxX - size.width)
    let y = min(max(origin.y, screen.minY), screen.maxY - size.height)
    return CGPoint(x: x, y: y)
}

/// Faixa de zoom permitida ao redimensionar a janela pelas bordas.
public let zoomRange: ClosedRange<CGFloat> = 0.8...2.5

/// Novo zoom quando o usuário arrasta a borda de `current` para `proposed`: manda o lado que mais mudou
/// em proporção (arrastar só a lateral ou só o topo também funciona), limitado a `zoomRange`.
public func resizedScale(current: CGSize, proposed: CGSize, scale: CGFloat) -> CGFloat {
    guard current.width > 0, current.height > 0 else { return scale }
    let byWidth = proposed.width / current.width
    let byHeight = proposed.height / current.height
    let factor = abs(byWidth - 1) >= abs(byHeight - 1) ? byWidth : byHeight
    return min(max(scale * factor, zoomRange.lowerBound), zoomRange.upperBound)
}
