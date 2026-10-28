// Gera Resources/AppIcon.icns: o mesmo desenho do ícone vivo do Dock (só a conta indicada, com os anéis de sessão e de semana).
// Uso: swift scripts/make-icon.swift   (rodar de dentro da pasta do projeto)
import AppKit

let green = NSColor(red: 0.30, green: 0.76, blue: 0.48, alpha: 1)
let yellow = NSColor(red: 0.89, green: 0.73, blue: 0.23, alpha: 1)
let red = NSColor(red: 0.89, green: 0.34, blue: 0.30, alpha: 1)

/// Exemplo estático: a conta indicada, com os anéis de sessão e de semana.
let sampleName = "claude"
let sampleRings: [(Double, NSColor)] = [(30, green), (62, green)]

func ring(_ center: CGPoint, radius: CGFloat, width: CGFloat, percent: Double, color: NSColor) {
    NSColor(white: 0.22, alpha: 1).setStroke()
    let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    track.lineWidth = width
    track.stroke()
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * percent / 100, clockwise: true)
    arc.lineWidth = width
    arc.lineCapStyle = .round
    color.setStroke()
    arc.stroke()
}

func draw(canvas: CGFloat) {
    // Grade de ícones do macOS: o corpo ocupa 824 de 1024, com margem transparente.
    let s = canvas / 1024
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1).setFill()
    NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s).fill()

    let name = NSAttributedString(string: sampleName, attributes: [
        .font: NSFont.systemFont(ofSize: 150 * s, weight: .heavy), .foregroundColor: green,
    ])
    let size = name.size()
    name.draw(at: NSPoint(x: body.midX - size.width / 2, y: body.midY + 175 * s))

    let radius = 122 * s, width = 44 * s
    for (column, value) in sampleRings.enumerated() {
        let x = body.midX + (column == 0 ? -1 : 1) * 160 * s
        let y = body.midY - 70 * s
        ring(CGPoint(x: x, y: y), radius: radius, width: width, percent: value.0, color: value.1)
        let text = NSAttributedString(string: "\(Int(value.0))", attributes: [
            .font: NSFont.systemFont(ofSize: 120 * s, weight: .bold), .foregroundColor: NSColor.white,
        ])
        let t = text.size()
        text.draw(at: NSPoint(x: x - t.width / 2, y: y - t.height / 2))
    }
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(canvas: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(pixels: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(pixels: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Resources/AppIcon.icns gerado" : "iconutil falhou")
