import SwiftUI

/// A finite RO window, scaled to fit the viewport without expanding its controls.
struct ClassicGamePanel<Content: View>: View {
    let title: String
    let width: CGFloat
    let height: CGFloat
    var preferredOffset: CGSize = .zero
    var tracksCompanion = false
    var titleBarHeight: CGFloat = 17
    var closeHitSize: CGFloat = 44
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.companionHUDObstacles) private var obstacles
    @State private var position = CGSize.zero
    @GestureState private var translation = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, max(1, geometry.size.width - 16) / width,
                            max(1, geometry.size.height - 16) / height)
            let chrome = PanelChromeLayout(width: width, height: height, scale: scale,
                requestedHeight: titleBarHeight, closeSize: closeHitSize)
            let horizontalLimit = max(0, (geometry.size.width - width * scale) / 2)
            let verticalLimit = max(0, (geometry.size.height - height * scale) / 2)
            let origin = tracksCompanion ? companionWindowOffset(in: geometry.frame(in: .global),
                size: CGSize(width: width * scale, height: height * scale), obstacles: obstacles) : preferredOffset
            let x = min(horizontalLimit, max(-horizontalLimit, origin.width + position.width + translation.width))
            let y = min(verticalLimit, max(-verticalLimit, origin.height + position.height + translation.height))
            VStack(spacing: 0) {
                // One visual strip and one bottom border across the entire width.
                // Interaction is a separate pair of non-overlapping sibling regions.
                GameTitleBar(Text(verbatim: title), usesGameSkin: true, trailingContentInset: chrome.close.width)
                    .frame(width: width, height: chrome.headerHeight, alignment: .top)
                    .allowsHitTesting(false)
                    .overlay(alignment: .topLeading) {
                        Color.clear.frame(width: chrome.drag.width, height: chrome.drag.height)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(coordinateSpace: .global)
                                .updating($translation) { value, state, _ in state = value.translation }
                                .onEnded { value in
                                    position = CGSize(
                                        width: min(horizontalLimit, max(-horizontalLimit, origin.width + position.width + value.translation.width)) - origin.width,
                                        height: min(verticalLimit, max(-verticalLimit, origin.height + position.height + value.translation.height)) - origin.height)
                                })
                    }
                content()
                    .frame(width: width, height: max(0, height - chrome.headerHeight))
                    .clipped()
                    .contentShape(Rectangle())
            }
            .frame(width: width, height: height)
            .background(Color.white)
            .contentShape(Rectangle())
            .overlay { Rectangle().strokeBorder(Color.gameBoxBorder, lineWidth: 1).allowsHitTesting(false) }
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    ZStack(alignment: .topTrailing) {
                        Color.clear
                        ZStack {
                            GameTitleBarButtonBackground(isPressed: false)
                            Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                        }.frame(width: 11, height: 11).padding(.top, 3).padding(.trailing, 6)
                    }
                    .frame(width: chrome.close.width, height: chrome.close.height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close " + title)
            }
            .font(.game(size: 12))
            .foregroundStyle(Color.gameLabel)
            .scaleEffect(scale)
            .frame(width: width * scale, height: height * scale)
            .background {
                if tracksCompanion {
                    GeometryReader { window in
                        Color.clear.preference(key: CompanionWindowBounds.self, value: window.frame(in: .global))
                    }
                }
            }
            .offset(x: x, y: y)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}
