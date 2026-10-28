import AppKit
import SwiftUI
import UsoClaudeCore

/// Aceita o primeiro clique mesmo com o app inativo, para o 📌 responder de primeira,
/// e ajusta a janela quando o conteúdo muda de tamanho (ex.: carregando → anéis).
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window as? FloatingPanel, !window.isResizingByEdge else { return }
            window.fitContent(self.fittingSize)
        }
    }
}

/// Estado do pin observado pela view, para alternar sem recriar o conteúdo.
@MainActor
final class PinState: ObservableObject {
    @Published var isPinned: Bool

    init(isPinned: Bool) {
        self.isPinned = isPinned
    }
}

/// Zoom do conteúdo, alterado ao redimensionar a janela pelas bordas.
@MainActor
final class ZoomState: ObservableObject {
    @Published var scale: CGFloat

    init(scale: CGFloat) {
        self.scale = scale
    }
}

/// Mostra o conteúdo no tamanho natural vezes o zoom: textos e componentes crescem juntos, sem mudar o layout.
private struct ZoomedContent<Content: View>: View {
    @ObservedObject var zoom: ZoomState
    let content: Content
    @State private var natural: CGSize?

    var body: some View {
        content
            .fixedSize()
            .onGeometryChange(for: CGSize.self, of: \.size) { natural = $0 }
            .scaleEffect(zoom.scale, anchor: .topLeading)
            .frame(width: natural.map { $0.width * zoom.scale }, height: natural.map { $0.height * zoom.scale },
                   alignment: .topLeading)
    }
}

/// Bordas da janela que o usuário pode arrastar.
private struct ResizeEdges: OptionSet {
    let rawValue: Int
    static let left = ResizeEdges(rawValue: 1)
    static let right = ResizeEdges(rawValue: 2)
    static let bottom = ResizeEdges(rawValue: 4)
    static let top = ResizeEdges(rawValue: 8)
}

/// Conteúdo da janela: hospeda a view SwiftUI e trata o arraste das bordas e cantos.
/// Uma janela sem borda não tem as alças de redimensionar do macOS, então elas são feitas aqui.
private final class ResizableContainer: NSView {
    private static let band: CGFloat = 6
    /// Perto dos cantos a borda conta como canto.
    private static let corner: CGFloat = 18

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Pixel 100% transparente deixa o clique passar para a janela de baixo; com 1% de opacidade
        // os cantos arredondados continuam invisíveis, mas recebem o clique para redimensionar.
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.01).cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    private func edges(at point: NSPoint) -> ResizeEdges {
        guard bounds.contains(point) else { return [] }
        let b = Self.band, c = Self.corner
        let nearLeft = point.x < b, nearRight = point.x > bounds.maxX - b
        let nearBottom = point.y < b, nearTop = point.y > bounds.maxY - b
        guard nearLeft || nearRight || nearBottom || nearTop else { return [] }
        var edges: ResizeEdges = []
        if point.x < c { edges.insert(.left) }
        if point.x > bounds.maxX - c { edges.insert(.right) }
        if point.y < c { edges.insert(.bottom) }
        if point.y > bounds.maxY - c { edges.insert(.top) }
        // Fora da região de canto, vale só a borda que o mouse está tocando.
        if edges.rawValue.nonzeroBitCount < 2 {
            edges = []
            if nearLeft { edges.insert(.left) }
            if nearRight { edges.insert(.right) }
            if nearBottom { edges.insert(.bottom) }
            if nearTop { edges.insert(.top) }
        }
        return edges
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return super.hitTest(point) }
        return edges(at: convert(point, from: superview)).isEmpty ? super.hitTest(point) : self
    }

    override func mouseMoved(with event: NSEvent) {
        cursor(for: edges(at: convert(event.locationInWindow, from: nil)))?.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    private func cursor(for edges: ResizeEdges) -> NSCursor? {
        if edges.isEmpty { return nil }
        if #available(macOS 15.0, *) {
            var directions: NSCursor.FrameResizePosition
            switch edges {
            case [.top, .left]: directions = .topLeft
            case [.top, .right]: directions = .topRight
            case [.bottom, .left]: directions = .bottomLeft
            case [.bottom, .right]: directions = .bottomRight
            case .left: directions = .left
            case .right: directions = .right
            case .top: directions = .top
            default: directions = .bottom
            }
            return NSCursor.frameResize(position: directions, directions: .all)
        }
        return edges.isDisjoint(with: [.top, .bottom]) ? .resizeLeftRight : .resizeUpDown
    }

    override func mouseDown(with event: NSEvent) {
        let edges = edges(at: convert(event.locationInWindow, from: nil))
        guard !edges.isEmpty, let window = window as? FloatingPanel else { return super.mouseDown(with: event) }
        window.trackEdgeResize(from: event, edges: edges)
    }
}

/// Janela sem borda que pode ficar fixa na frente dos outros apps.
/// Arrastar os cantos ou os lados muda o zoom do conteúdo. Guarda a posição, o zoom e o estado do pin entre execuções.
@MainActor
final class FloatingPanel: NSPanel {
    private static let pinnedKey = "pinned"
    private static let originKey = "windowOrigin"
    private static let zoomKey = "zoom"

    let pin: PinState
    let zoom: ZoomState
    private(set) var isResizingByEdge = false

    var isPinned: Bool {
        get { pin.isPinned }
        set {
            pin.isPinned = newValue
            UserDefaults.standard.set(newValue, forKey: Self.pinnedKey)
            applyPin()
        }
    }

    init() {
        pin = PinState(isPinned: UserDefaults.standard.bool(forKey: Self.pinnedKey))
        let saved = UserDefaults.standard.double(forKey: Self.zoomKey)
        zoom = ZoomState(scale: saved > 0 ? min(max(saved, zoomRange.lowerBound), zoomRange.upperBound) : 1)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        applyPin()
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveOrigin() }
        }
    }

    override var canBecomeKey: Bool { true }

    func setContent<V: View>(_ view: V) {
        let hosting = FirstMouseHostingView(rootView: ZoomedContent(zoom: zoom, content: view))
        // Só o tamanho intrínseco: sem os limites mín./máx. que o NSHostingView imporia à janela.
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.autoresizingMask = [.width, .height]
        let container = ResizableContainer()
        container.addSubview(hosting)
        contentView = container
        setContentSize(hosting.fittingSize)
        hosting.frame = container.bounds
    }

    /// Redimensiona mantendo o canto de cima fixo, para a janela não "pular" na tela.
    func fitContent(_ size: NSSize) {
        guard size != contentLayoutRect.size, size.width > 0, size.height > 0 else { return }
        let top = frame.maxY
        var newFrame = frameRect(forContentRect: NSRect(origin: frame.origin, size: size))
        newFrame.origin.y = top - newFrame.height
        setFrame(newFrame, display: true)
    }

    /// Volta ao tamanho original (zoom 1).
    func resetZoom() {
        setZoom(1)
    }

    private func setZoom(_ scale: CGFloat) {
        zoom.scale = scale
        UserDefaults.standard.set(Double(scale), forKey: Self.zoomKey)
    }

    // MARK: Redimensionar pelas bordas

    /// Acompanha o arraste de uma borda ou canto até soltar o mouse: o quanto a borda andou vira zoom,
    /// e a janela cresce mantendo fixas as bordas opostas.
    fileprivate func trackEdgeResize(from event: NSEvent, edges: ResizeEdges) {
        let start = frame
        let startScale = zoom.scale
        let startMouse = NSEvent.mouseLocation
        isResizingByEdge = true
        defer {
            isResizingByEdge = false
            if let hosting = contentView?.subviews.first { fitContent(hosting.fittingSize) }
        }
        while let next = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - startMouse.x, dy = mouse.y - startMouse.y
            var proposed = start.size
            if edges.contains(.right) { proposed.width += dx }
            if edges.contains(.left) { proposed.width -= dx }
            if edges.contains(.top) { proposed.height += dy }
            if edges.contains(.bottom) { proposed.height -= dy }
            let scale = resizedScale(current: start.size, proposed: proposed, scale: startScale)
            setZoom(scale)
            let size = NSSize(width: (start.width * scale / startScale).rounded(),
                              height: (start.height * scale / startScale).rounded())
            // A borda arrastada se move; a oposta fica onde estava (por padrão, o canto de cima à esquerda).
            let x = edges.contains(.left) ? start.maxX - size.width : start.minX
            let y = edges.contains(.top) ? start.minY : start.maxY - size.height
            setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }
    }

    func restoreOrigin() {
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            // Reaproveita a posição só se ela ainda cair numa tela, puxando a janela inteira para dentro.
            if let origin = clampedOrigin(NSPointFromString(saved), size: frame.size,
                                          screens: NSScreen.screens.map(\.visibleFrame)) {
                setFrameOrigin(origin)
                return
            }
        }
        if let screen = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(x: screen.maxX - frame.width - 20, y: screen.maxY - frame.height - 20))
        }
    }

    private func saveOrigin() {
        UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: Self.originKey)
    }

    private func applyPin() {
        level = isPinned ? .floating : .normal
        collectionBehavior = isPinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
    }
}
