import Foundation
import Testing
@testable import RagnarokGame

@Test func companionWindowAvoidsHUDInBothOrientations() {
    for size in [CGSize(width: 460, height: 680), CGSize(width: 680, height: 460)] {
        let viewport = CGRect(origin: CGPoint(x: 8, y: 24), size: size)
        let window = CGSize(width: 344, height: 278)
        let hud = CGRect(x: viewport.minX, y: viewport.maxY - 130, width: size.width, height: 130)
        let shift = companionWindowOffset(in: viewport, size: window, obstacles: [hud])
        let result = CGRect(x: viewport.midX + shift.width - window.width / 2,
                            y: viewport.midY + shift.height - window.height / 2,
                            width: window.width, height: window.height)
        #expect(viewport.contains(result))
        #expect(!hud.intersects(result))
    }
}

@Test func companionWindowStaysReachableInCrowdedLandscape() {
    let viewport = CGRect(x: 0, y: 0, width: 568, height: 320)
    let size = CGSize(width: 344, height: 294)
    let obstacles = [CGRect(x: 0, y: 0, width: 240, height: 90),CGRect(x: 0, y: 204, width: 568, height: 116)]
    let shift = companionWindowOffset(in: viewport, size: size, obstacles: obstacles)
    #expect(abs(shift.width) <= (viewport.width - size.width) / 2)
    #expect(abs(shift.height) <= (viewport.height - size.height) / 2)
    #expect(companionWindowOffset(in: viewport, size: size, obstacles: []) == .zero)
}
