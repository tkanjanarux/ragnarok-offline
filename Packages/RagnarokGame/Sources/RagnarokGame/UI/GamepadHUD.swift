#if os(iOS)
import SwiftUI

struct GamepadHUD: View {
    let controller: GamepadController
    var body: some View {
        if let name = controller.connectedName {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name).lineLimit(1)
                    Spacer(minLength: 3)
                    Button("Controls") { controller.helpVisible.toggle() }
                }
                Text(controller.targetName).lineLimit(1)
                Text("\(controller.companionName)").lineLimit(1)
                if !controller.message.isEmpty { Text(controller.message).lineLimit(2) }
            }.font(.game(size: 10)).foregroundStyle(Color.gameLabel)
                .buttonStyle(ROCompactButtonStyle(visualHeight: 20, hitHeight: 28))
                .padding(4).frame(width: 220)
                .background { GameStripeView().allowsHitTesting(false) }
                .overlay { Rectangle().strokeBorder(Color.gameBoxBorder).allowsHitTesting(false) }
        }
    }
}
struct GamepadHelp: View {
    let controller: GamepadController
    private func label(_ key: String) -> String { controller.labels[key] ?? key }
    var body: some View {
        GeometryReader { bounds in
            OriginalROPanel(title: "Controller", width: min(360, bounds.size.width - 24), height: min(390, bounds.size.height - 24), onClose: { controller.helpVisible = false }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Left stick: walk relative to camera. Right stick: orbit camera.")
                        Text("Release: finish the short accepted step; not an instant server stop.")
                        Text("\(label("lb")) / \(label("rb")): previous / next visible monster")
                        Text("Faint ring: directional preview. Gem: explicit lock. Solid ring: current attack.")
                        Text("Without a lock, point the left stick and press attack or an offensive shortcut. Release or redirect the stick to move again. Shoulders or touching a monster lock it; cancel unlocks.")
                        Text("\(label("a")): approach and attack continuously. Selected nearby NPC: talk. No target nearby: loot.")
                        Text("\(label("b")): cancel target / close menu. Menu: Options.")
                        Text("\(label("x")) / \(label("y")): shortcut row 1, slots 1 / 2 (same as left-trigger shortcuts)")
                        Text("\(label("lt")) + \(label("a"))/\(label("b"))/\(label("x"))/\(label("y")): row 1, slots 1–4")
                        Text("\(label("rt")) + \(label("a"))/\(label("b"))/\(label("x"))/\(label("y")): row 1, slots 5–8. Both triggers: right wins.")
                        Text("D-pad up: Follow · right: Assist · down: Stop · left: Hunt (whole active team)")
                        Text("\(controller.companionName)")
                        Text("Configure items/skills in the existing shortcut bar. Passive and ground skills are not cast by the controller; ground skills use touch controls.")
                        Text("One command per press; attacks repeat on the selected monster only. Move, cancel or change target to end attacking. Release controls after touching the map, closing windows or returning to the app. Transactions and text entry use touch.")
                        Button("Close") { controller.helpVisible = false }
                    }.padding(10)
                }
            }
        }
    }
}
#endif
