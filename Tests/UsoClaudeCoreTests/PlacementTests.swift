import CoreGraphics
import Testing
@testable import UsoClaudeCore

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
private let size = CGSize(width: 300, height: 230)

@Test func keepsOriginWhenWholeWindowFits() {
    #expect(clampedOrigin(CGPoint(x: 100, y: 100), size: size, screens: [screen]) == CGPoint(x: 100, y: 100))
}

@Test func pullsBackWindowPastTopRight() {
    // Origem dentro da tela, mas a janela passaria da borda direita e de cima.
    #expect(clampedOrigin(CGPoint(x: 1400, y: 860), size: size, screens: [screen]) == CGPoint(x: 1140, y: 645))
}

@Test func originOnNoScreenIsRejected() {
    #expect(clampedOrigin(CGPoint(x: 5000, y: 5000), size: size, screens: [screen]) == nil)
}

@Test func widthDragScalesWholeWindow() {
    #expect(resizedScale(current: CGSize(width: 300, height: 200), proposed: CGSize(width: 450, height: 200), scale: 1) == 1.5)
}

@Test func heightDragScalesWholeWindow() {
    #expect(resizedScale(current: CGSize(width: 300, height: 200), proposed: CGSize(width: 300, height: 100), scale: 1) == 0.8)
}

@Test func cornerDragFollowsLargerChange() {
    #expect(resizedScale(current: CGSize(width: 300, height: 200), proposed: CGSize(width: 330, height: 300), scale: 2) == 2.5)
    #expect(resizedScale(current: CGSize(width: 600, height: 400), proposed: CGSize(width: 660, height: 410), scale: 2) == 2.2)
}
