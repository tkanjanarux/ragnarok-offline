import SwiftUI

/// A finite RO window, scaled to fit the viewport without expanding its controls.
struct ClassicGamePanel<Content: View>: View {
    let title: String
    let width: CGFloat
    let height: CGFloat
    var preferredOffset: CGSize = .zero
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var position = CGSize.zero
    @GestureState private var translation = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, max(1, geometry.size.width - 16) / width,
                            max(1, geometry.size.height - 16) / height)
            let horizontalLimit = max(0, (geometry.size.width - width * scale) / 2)
            let verticalLimit = max(0, (geometry.size.height - height * scale) / 2)
            let x = min(horizontalLimit, max(-horizontalLimit, preferredOffset.width + position.width + translation.width))
            let y = min(verticalLimit, max(-verticalLimit, preferredOffset.height + position.height + translation.height))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Drag only the title area. The close button is a sibling overlay,
                    // so its tap cannot be intercepted by the window drag recognizer.
                    GameTitleBar(Text(verbatim: title), usesGameSkin: true)
                        .frame(width: max(0, width - 44 / scale))
                        .contentShape(Rectangle())
                        .gesture(DragGesture(coordinateSpace: .global)
                            .updating($translation) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                position = CGSize(
                                    width: min(horizontalLimit, max(-horizontalLimit, preferredOffset.width + position.width + value.translation.width)) - preferredOffset.width,
                                    height: min(verticalLimit, max(-verticalLimit, preferredOffset.height + position.height + value.translation.height)) - preferredOffset.height)
                            })
                    Color.clear.frame(width: 44 / scale)
                }
                .frame(height: 17)
                .background { GameImage("basic_interface/titlebar_mid.bmp") { $0.resizable() }.allowsHitTesting(false) }
                content()
                    .frame(width: width, height: height - 17)
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
                    .frame(width: 44 / scale, height: 44 / scale)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close " + title)
            }
            .font(.game(size: 12))
            .foregroundStyle(Color.gameLabel)
            .scaleEffect(scale)
            .frame(width: width * scale, height: height * scale)
            .offset(x: x, y: y)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}
