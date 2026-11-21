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

// Reserve a small exterior margin on displays with a home indicator.
func bottomHUDMargin(for bottomInset: CGFloat) -> CGFloat {
    min(bottomInset, 12)
}
