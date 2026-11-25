import SwiftUI

/// Local to the restored windows: visual button height and its allocated hit row
/// are independent. Padding belongs to layout, never to an overlapping overlay.
struct ROCompactButtonStyle: ButtonStyle {
    var visualHeight: CGFloat = 22
    var hitHeight: CGFloat = 30
    func makeBody(configuration: Configuration) -> some View {
        GameButtonStyle().makeBody(configuration: configuration)
            .frame(height: visualHeight)
            .padding(.vertical, max(0, (hitHeight - visualHeight) / 2))
            .contentShape(Rectangle())
    }
}

struct OriginalROPanel<Content: View>: View {
    let title: String
    let width: CGFloat
    let height: CGFloat
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        ClassicGamePanel(title: title, width: width, height: height,
                         titleBarHeight: 28, closeHitSize: 28, onClose: onClose) {
            content()
                .font(.game(size: 12))
                .foregroundStyle(Color.gameLabel)
                .buttonStyle(ROCompactButtonStyle())
                .background { GameStripeView().allowsHitTesting(false) }
                .environment(\.colorScheme, .light)
        }
    }
}

struct ROTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).foregroundStyle(Color.black)
            .padding(.horizontal, 5).padding(.vertical, 6)
            .background(Color.white)
            .overlay { Rectangle().strokeBorder(Color.gameBoxBorder, lineWidth: 1).allowsHitTesting(false) }
    }
}

struct ROTabs<Value: Hashable>: View {
    let choices: [(Value, String)]
    @Binding var selection: Value
    var body: some View {
        HStack(spacing: 0) {
            ForEach(choices, id: \.0) { value, title in
                Button { selection = value } label: {
                    Text(LocalizedStringKey(title)).font(.game(size: 11))
                        .foregroundStyle(value == selection ? Color.blue : Color.gameLabel)
                        .padding(.horizontal, 3).frame(maxWidth: .infinity, minHeight: 30)
                        .background(value == selection ? Color.white : Color(white: 0.94))
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(value == selection ? Color.blue.opacity(0.55) : Color.gameBoxBorder).frame(height: value == selection ? 2 : 1)
                        }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(value == selection ? .isSelected : [])
            }
        }
    }
}

struct ROCheck: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 7) {
                ZStack {
                    Rectangle().fill(Color.white).overlay { Rectangle().strokeBorder(Color.gameBoxBorder) }
                    if isOn { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                }.frame(width: 13, height: 13)
                Text(LocalizedStringKey(title))
                Spacer(minLength: 0)
            }.frame(minHeight: 30).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityValue(isOn ? "On" : "Off")
    }
}

struct ROProgress: View {
    let value: Double
    let total: Double
    var body: some View {
        GeometryReader { size in
            ZStack(alignment: .leading) {
                Color.white
                Rectangle().fill(Color(red: 0.48, green: 0.57, blue: 0.79))
                    .frame(width: size.size.width * (total > 0 ? min(1, max(0, value / total)) : 0))
            }.overlay { Rectangle().strokeBorder(Color.gameBoxBorder) }
        }.frame(height: 7)
    }
}

/// Resolve the player's existing GRF skin at runtime; no artwork is bundled.
struct ROSkinButton: View {
    let title: String
    let image: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                GameImage(image).frame(width: 24, height: 26)
                Text(LocalizedStringKey(title)).font(.game(size: 11))
            }.frame(minHeight: 30).contentShape(Rectangle())
        }.buttonStyle(.plain).opacity(isEnabled ? 1 : 0.5)
    }
}
