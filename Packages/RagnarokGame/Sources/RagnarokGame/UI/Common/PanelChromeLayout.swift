import Foundation

/// Logical coordinates before the panel's uniform scale. Both hit regions are
/// disjoint and the content starts below them, including reduced viewports.
struct PanelChromeLayout {
    let headerHeight: CGFloat
    let close: CGRect
    let drag: CGRect
    init(width: CGFloat, height: CGFloat, scale: CGFloat, requestedHeight: CGFloat, closeSize: CGFloat) {
        let hitWidth = min(max(0, width), closeSize / max(0.01, scale))
        headerHeight = min(max(0, height), max(requestedHeight, closeSize / max(0.01, scale)))
        close = CGRect(x: max(0, width - hitWidth), y: 0, width: hitWidth, height: headerHeight)
        drag = CGRect(x: 0, y: 0, width: max(0, width - hitWidth), height: headerHeight)
    }
}
