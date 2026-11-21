import SwiftUI

struct MapHUDViewport<Content: View>: View {
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        GeometryReader { viewport in
            content(viewport.size)
        }
        #if os(iOS)
        // Include the horizontal container insets in both the size and origin of the HUD.
        .ignoresSafeArea(.container, edges: .horizontal)
        #endif
    }
}
