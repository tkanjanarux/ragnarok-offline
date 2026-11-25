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

/// Preserve the caller's full content canvas (some original RO windows have
/// fixed-height footers). Fit the added close-target clearance by scaling the
/// complete window, not by clipping those controls off its bottom.
struct PanelWindowLayout {
    let scale: CGFloat
    let height: CGFloat
    let contentHeight: CGFloat
    let chrome: PanelChromeLayout
    init(width: CGFloat, height: CGFloat, available: CGSize, requestedHeader: CGFloat, closeSize: CGFloat) {
        contentHeight = max(0, height - requestedHeader)
        let availableWidth = max(1, available.width), availableHeight = max(1, available.height)
        let physicalClose = min(closeSize, availableHeight / 2)
        scale = min(1, availableWidth / max(1, width), availableHeight / max(1, height),
                    (availableHeight - physicalClose) / max(1, contentHeight))
        let header = max(requestedHeader, physicalClose / scale)
        self.height = contentHeight + header
        chrome = PanelChromeLayout(width: width, height: self.height, scale: scale,
                                   requestedHeight: requestedHeader, closeSize: physicalClose)
    }
}
