import Foundation

/// +Y is forward in game coordinates; the GRF navi_grid1_4 image points up.
/// Rotate geometry, not the camera-facing UI. UV top corresponds to game +Y.
enum NavigationArrowGeometry {
    static let corners: [SIMD2<Float>] = [[-1,-1], [1,-1], [1,1], [1,1], [-1,1], [-1,-1]]
    static let uv: [SIMD2<Float>] = corners.map { [($0.x + 1) / 2, (1 - $0.y) / 2] }
    static func points(direction: SIMD2<Int>) -> [SIMD2<Float>] {
        let dx = Float(direction.x), dy = Float(direction.y)
        let length = max(1, sqrt(dx * dx + dy * dy))
        let forward = SIMD2(dx / length, dy / length)
        let right = SIMD2(forward.y, -forward.x)
        return corners.map { SIMD2<Float>(repeating: 0.5) + (right * $0.x + forward * $0.y) * 0.7 }
    }
    static func position(_ p: SIMD2<Float>, tile: SIMD2<Int>, altitudes h: SIMD4<Float>) -> SIMD3<Float> {
        let altitude = p.y <= p.x ? h.x + (h.y - h.x) * p.x + (h.w - h.y) * p.y
            : h.x + (h.w - h.z) * p.x + (h.z - h.x) * p.y
        return [Float(tile.x) + p.x, -(altitude + 0.12), Float(tile.y) + p.y]
    }
}
