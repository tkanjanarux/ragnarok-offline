import SwiftUI

struct MapHUDViewport<Content: View>: View {
    @ViewBuilder var content: (CGSize, CGFloat) -> Content

    var body: some View {
        GeometryReader { safe in
            #if os(iOS)
            GeometryReader { viewport in
                let bottomInset = max(0, viewport.size.height - safe.size.height)
                content(viewport.size, bottomInset)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            #else
            content(safe.size, 0)
            #endif
        }
        #if os(iOS)
        .ignoresSafeArea(.container, edges: .horizontal)
        #endif
    }
}

// Extend the panel to the edge. Keep the center of even a 28-point button
// at least 6 points above the system gesture inset.
func bottomHUDControlPadding(for bottomInset: CGFloat) -> CGFloat {
    min(bottomInset, max(8, bottomInset - 8))
}
