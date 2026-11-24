import SwiftUI

struct FollowersView: View {
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var name = ""
    @State private var confirming: FollowerState.Operation?
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: session.followers.kind.rawValue, width: min(440, bounds.size.width - 24), height: min(600, bounds.size.height - 24), onClose: { session.followers.visible = false }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Type", selection: Binding(get: { session.followers.kind }, set: { session.followers.kind = $0 })) {
                            ForEach(FollowerState.Kind.allCases, id: \.self) { kind in Text(kind.rawValue).tag(kind) }
                        }.pickerStyle(.segmented).disabled(session.followers.pending != nil)
                        if session.followers.kind == .homunculus {
                            homunculus
                        } else { mercenary }
                        if session.followers.actorID != nil {
                            HStack {
                                Button("Follow") { session.moveFollowerToOwner() }
                                Button("Attack once") { session.moveFollowerToOwner(attack: true) }
                            }.frame(minHeight: 44)
                            Button("Move to selected target") { session.moveFollowerToSelectedTarget() }.frame(minHeight: 44)
                            Text("Attack once requires a target within reach. Move closer first if needed.").foregroundStyle(.secondary)
                            ForEach(session.followers.skills, id: \.id) { skill in
                                HStack {
                                    Button(context.skillInfoTable.localizedSkillName(forSkillID: Int(skill.id)) ?? skill.name) { session.useFollowerSkill(skill.id) }
                                        .disabled(skill.level == 0 || skill.inf == 0)
                                    Text("Lv. \(skill.level) · SP \(skill.sp)")
                                    if session.followers.kind == .homunculus && skill.upgradable != 0 {
                                        Button("+") { session.useFollowerSkill(skill.id, upgrade: true) }.disabled(session.followers.pending != nil)
                                    }
                                }.frame(minHeight: 44)
                            }
                            Button(session.followers.kind == .homunculus ? "Delete homunculus" : "Dismiss mercenary") { confirming = .dismiss }
                                .frame(minHeight: 44).disabled(session.followers.pending != nil)
                        }
                        if let message = session.followers.message { Text(message) }
                    }.padding(12)
                }.font(.game(size: 13)).buttonStyle(.game)
            }
        }
        .confirmationDialog(confirming == .feed ? "Feed the homunculus? Overfeeding can reduce intimacy." : "Permanently dismiss this follower?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Confirm") { if let command = confirming { session.followerCommand(command) }; confirming = nil }
            Button("Cancel", role: .cancel) { confirming = nil }
        }
    }
    @ViewBuilder private var homunculus: some View {
        if let info = session.followers.homunculus {
            Text("\(info.name) · Lv. \(info.level)").fontWeight(.bold)
            Text("HP \(info.hp)/\(info.maxHp) · SP \(info.sp)/\(info.maxSp)")
            Text("Hunger \(info.hunger)/100 · Intimacy \(info.intimacy)")
            Text("EXP \(info.exp)/\(info.expNext) · Skill points \(info.skillPoints)")
            Button("Feed") { confirming = .feed }.frame(minHeight: 44).disabled(session.followers.pending != nil)
            Button(session.followers.homAutoFeed == true ? "Disable auto feed" : "Enable auto feed") { session.setHomunculusAutoFeed(session.followers.homAutoFeed != true) }
                .frame(minHeight: 44).disabled(session.followers.pending != nil)
            if info.flags & 1 == 0 {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                Button("Rename") { session.renameHomunculus(name) }.frame(minHeight: 44).disabled(name.isEmpty || session.followers.pending != nil)
            }
        } else { Text("No active homunculus. Use Call Homunculus or Resurrection from your skill window.") }
        Text("Use Rest from your skill window to preserve your homunculus.")
    }
    @ViewBuilder private var mercenary: some View {
        if let info = session.followers.mercenary {
            Text("\(info.name) · Lv. \(info.level)").fontWeight(.bold)
            Text("HP \(info.hp)/\(info.maxHP) · SP \(info.sp)/\(info.maxSP)")
            Text("Faith \(info.faith) · Kills \(info.kills) · Calls \(info.calls)")
            Text("Contract ends: " + Date(timeIntervalSince1970: Double(info.expires)).formatted())
        } else { Text("No active mercenary. Use a mercenary contract from your inventory.") }
    }
}
