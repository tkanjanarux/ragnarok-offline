import SwiftUI

struct CompanionHUDFrames: PreferenceKey {
    static var defaultValue: [CGRect] { [] }
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

extension EnvironmentValues {
    @Entry var companionHUDObstacles: [CGRect] = []
}

// The visible area of overlap changes at a HUD edge. Evaluate those points and
// the screen centre, then keep the nearest position in a tie. The drag offset is
// applied by the window afterwards so it remains under the player's control.
func companionWindowOffset(in viewport: CGRect, size: CGSize, obstacles: [CGRect]) -> CGSize {
    let margin: CGFloat = 4
    let centre = CGPoint(x: viewport.midX - size.width / 2, y: viewport.midY - size.height / 2)
    let visible = obstacles.filter { !$0.isEmpty && $0.intersects(viewport) }
    guard !visible.isEmpty else { return .zero }
    let xs = [centre.x] + visible.flatMap { [$0.minX - size.width - margin, $0.maxX + margin] }
    let ys = [centre.y] + visible.flatMap { [$0.minY - size.height - margin, $0.maxY + margin] }
    var best = CGSize.zero
    var smallestArea = CGFloat.infinity
    var shortest = CGFloat.infinity
    for x in xs {
        for y in ys {
            let origin = CGPoint(x: min(viewport.maxX - size.width, max(viewport.minX, x)),
                                 y: min(viewport.maxY - size.height, max(viewport.minY, y)))
            let frame = CGRect(origin: origin, size: size)
            let area = visible.reduce(CGFloat.zero) { sum, hud in
                let overlap = frame.intersection(hud)
                return overlap.isNull ? sum : sum + overlap.width * overlap.height
            }
            let dx = origin.x - centre.x, dy = origin.y - centre.y
            let distance = dx * dx + dy * dy
            if area < smallestArea || (area == smallestArea && distance < shortest) {
                smallestArea = area
                shortest = distance
                best = CGSize(width: dx, height: dy)
            }
        }
    }
    return best
}
