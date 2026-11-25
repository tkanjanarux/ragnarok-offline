import Foundation

struct MinimapProjection {
    var width: Int
    var height: Int
    var size: Double = 96
    var imageWidth: Double = 512
    var imageHeight: Double = 512
    var zoomFactor: Int = 1
    var player = SIMD2<Int>(0, 0)

    var displaySize: CGSize {
        guard zoomFactor != 1 else { return CGSize(width: size, height: size) }
        let scale = max(size / Double(zoomFactor * 40), size / min(imageWidth, imageHeight))
        return CGSize(width: imageWidth * scale, height: imageHeight * scale)
    }

    var center: CGPoint {
        guard zoomFactor != 1 else { return CGPoint(x: size / 2, y: size / 2) }
        let anchor = normalized(player)
        let display = displaySize
        return CGPoint(
            x: min(max(size / 2 + (0.5 - anchor.x) * display.width, size - display.width / 2), display.width / 2),
            y: min(max(size / 2 + (0.5 - anchor.y) * display.height, size - display.height / 2), display.height / 2)
        )
    }

    func point(_ position: SIMD2<Int>) -> CGPoint {
        let projected = normalized(position)
        return CGPoint(x: center.x + (projected.x - 0.5) * displaySize.width,
                       y: center.y + (projected.y - 0.5) * displaySize.height)
    }

    func contains(_ position: SIMD2<Int>) -> Bool {
        position.x >= 0 && position.y >= 0 && position.x < width && position.y < height
    }

    private func normalized(_ position: SIMD2<Int>) -> CGPoint {
        let dimension = Double(max(1, max(width, height)))
        return CGPoint(x: (dimension - Double(width)) / (2 * dimension) + Double(position.x) / dimension,
                       y: (dimension + Double(height)) / (2 * dimension) - Double(position.y) / dimension)
    }
}
