import SwiftUI
import RagnarokModels

struct GameSettingsView: View {
    let section: String
    let onClose: () -> Void
    @Environment(GameSession.self) private var game
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @AppStorage("ro.bgmVolume") private var bgm = 0.8
    @AppStorage("ro.effectVolume") private var sound = 0.5
    @AppStorage("ro.frameRate") private var frameRate = 60
    @AppStorage("ro.effects") private var effects = true
    @AppStorage("ro.fog") private var fog = true
    @State private var row = 0
    @State private var column = 0
    var body: some View {
        GeometryReader { bounds in
            OriginalROPanel(title: section, width: min(320,bounds.size.width - 24), height: min(section == "BM/Shortcut Settings" ? 430 : 230,bounds.size.height - 24), onClose: onClose) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if section == "Sound" {
                            Text("Background music: \(Int(bgm * 100))%")
                            volume($bgm)
                            Text("Sound effects: \(Int(sound * 100))%")
                            volume($sound)
                            Button("Test sound") { game.audioPlayer.playButtonSoundEffect() }.frame(minHeight: 30)
                        } else if section == "Settings" {
                            Text("Frame rate")
                            ROTabs(choices: [(30, "30 FPS"), (60, "60 FPS")], selection: $frameRate)
                            ROCheck(title: "Visual effects", isOn: $effects)
                            ROCheck(title: "Map fog", isOn: $fog)
                        } else { shortcuts }
                    }.padding(10).font(.game(size: 12))
                }
            }
        }
        .onChange(of: bgm) { game.audioPlayer.applyVolumes() }
        .onChange(of: sound) { game.audioPlayer.applyVolumes() }
    }
    private func volume(_ value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Button("−") { value.wrappedValue = max(0, value.wrappedValue - 0.05) }.frame(width: 30)
            Slider(value: value, in: 0...1).tint(Color(red: 0.48, green: 0.57, blue: 0.79))
            Button("+") { value.wrappedValue = min(1, value.wrappedValue + 0.05) }.frame(width: 30)
        }
    }
    @ViewBuilder private var shortcuts: some View {
        Text("Row")
        ROTabs(choices: session.shortcutList.rows.indices.map { ($0, String($0 + 1)) }, selection: $row)
        Text("Slot")
        ROTabs(choices: (0..<8).map { ($0, String($0 + 1)) }, selection: $column)
        HStack {
            ShortcutIconView(shortcut: session.shortcutList.rows[row][column]).frame(width: 36,height: 36)
            Button("Clear slot") { session.removeShortcut(atRow: row, column: column) }.frame(minHeight: 30)
        }
        Text("Choose an item or learned skill for this slot.")
        DisclosureGroup("Inventory items") {
            ForEach(session.inventory.items.values.sorted(), id: \.index) { item in
                Button(context.itemInfoTable.localizedIdentifiedItemName(forItemID: item.itemID) ?? "Item \(item.itemID)") {
                    session.setShortcut(.item(itemID: item.itemID), atRow: row, column: column)
                }.frame(minHeight: 30)
            }
        }
        DisclosureGroup("Skills") {
            ForEach(session.skillList.sortedSkills.filter { $0.level > 0 && !$0.isPassiveSkill }, id: \.skillID) { skill in
                Menu(context.skillInfoTable.localizedSkillName(forSkillID: skill.skillID) ?? "Skill \(skill.skillID)") {
                    ForEach(1...skill.level, id: \.self) { level in
                        Button("Level \(level)") { session.setShortcut(.skill(skillID: skill.skillID, level: level), atRow: row, column: column) }
                    }
                }.frame(minHeight: 30)
            }
        }
    }
}
