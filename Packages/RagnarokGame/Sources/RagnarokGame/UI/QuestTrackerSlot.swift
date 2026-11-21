import Foundation

/// Find space along the leading edge, between the actual HUD controls for this frame.
func questTrackerSlot(in size: CGSize, obstacles: [CGRect]) -> CGRect? {
    let margin: CGFloat = 8
    let width = min(230, size.width * 0.42)
    guard width > 0, !obstacles.isEmpty else { return nil }
    let column = CGRect(x: margin, y: margin, width: width, height: max(0, size.height - 2 * margin))
    let blocked = obstacles.filter { !$0.isEmpty }
        .map { $0.insetBy(dx: -margin, dy: -margin) }
        .filter { $0.intersects(column) }
        .sorted { $0.minY < $1.minY }

    var top = column.minY
    for rect in blocked {
        let bottom = min(rect.minY, column.maxY)
        if bottom - top >= 36 {
            return CGRect(x: margin, y: top, width: width, height: bottom - top)
        }
        top = max(top, rect.maxY)
    }
    guard column.maxY - top >= 36 else { return nil }
    return CGRect(x: margin, y: top, width: width, height: column.maxY - top)
}
