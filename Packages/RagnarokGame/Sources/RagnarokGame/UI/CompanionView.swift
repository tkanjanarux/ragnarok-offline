import SwiftUI

/// RO party-list styling: game skin title/buttons, renewal job icons and white rows.
struct CompanionView: View {
    var close: () -> Void
    @Environment(PlaySession.self) private var session
    @State private var selected: UInt32?
    @State private var equipmentProfile: UInt32?
    @State private var confirmRelease: UInt32?
    private var row: CompanionProfile? { session.companions.profiles.first { $0.id == selected } }
    private var enabled: Bool { session.companions.ready && session.companions.available && !session.companions.pending }

    var body: some View {
        ClassicGamePanel(title: "Companions", width: 360, height: 440, onClose: close) {
            VStack(spacing: 4) {
                HStack {
                    Text("Roster \(session.companions.profiles.count)/9")
                    Spacer()
                    Text("Active \(session.companions.activeCount)/\(CompanionState.activeLimit)")
                }.padding(.horizontal, 8).frame(height: 22)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.companions.profiles) { member in
                            Button { selected = member.id } label: {
                                HStack(spacing: 8) {
                                    GameImage("renewalparty/icon_jobs_\(member.job)\(member.mode == 4 ? "_die" : "").bmp").frame(width: 26, height: 32)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(verbatim: member.name).font(.game(weight: .bold))
                                        Text("Lv. \(member.level) / Job \(member.jobLevel)  \(member.jobName)").font(.game(size: 10))
                                    }
                                    Spacer()
                                    Text(member.stateName).font(.game(size: 10))
                                }.padding(.horizontal, 6).frame(height: 46)
                                .foregroundStyle(Color.gameLabel)
                                .background(selected == member.id ? Color(red: 0.82, green: 0.89, blue: 1) : Color.white)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if session.companions.ready && session.companions.profiles.isEmpty {
                            Text("Recruit a companion below or visit the recruiter in Prontera.")
                                .font(.game(size: 11)).padding(10)
                        }
                    }
                }.frame(height: 107).overlay { Rectangle().strokeBorder(Color.gameBoxBorder).allowsHitTesting(false) }
                if let row {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Base and Job follow your character")
                        Text(row.hp < 0 ? "Ready for first summon" : "HP \(row.hp)  SP \(row.sp)\(row.job == 8 ? "  Gems \(row.gems)" : "")")
                    }.font(.game(size: 10)).frame(maxWidth: .infinity, alignment: .leading).frame(height: 30)
                } else { Text("Select a companion").font(.game(size: 11)).frame(height: 30) }
                HStack(spacing: 4) {
                    action(row?.active == true ? "Reserve" : "Summon", verb: row?.active == true ? "bench" : "summon", disabled: row == nil || (row?.active == false && session.companions.activeCount >= CompanionState.activeLimit))
                    action("Follow", verb: "follow", disabled: row?.active != true)
                    action("Assist", verb: "assist", disabled: row?.active != true)
                    action("Stop", verb: "stop", disabled: row?.active != true)
                }
                if let hunting = session.companions.nearbyHunt {
                    Button(hunting ? "Nearby Hunt: ON" : "Nearby Hunt: OFF") {
                        session.companionCommand(hunting ? "hunt off" : "hunt on")
                    }.buttonStyle(.game).disabled(!enabled)
                }
                if let row {
                    Menu("Preset: " + row.preset.capitalized) {
                        ForEach(["custom", "protect", "assist", "conserve"], id: \.self) { preset in
                            Button(preset == "conserve" ? "Conserve SP" : preset.capitalized) {
                                session.companionCommand("preset \(row.id) \(preset)")
                            }
                        }
                    }.disabled(!enabled)
                }
                HStack(spacing: 4) {
                    Text("Recruit:").font(.game(size: 10))
                    ForEach(["Knight", "Priest", "Wizard", "Hunter"], id: \.self) { job in
                        Button(["Knight":"Swordman", "Priest":"Acolyte", "Wizard":"Mage", "Hunter":"Archer"][job] ?? job) { session.companionCommand("recruit \(job.lowercased())") }
                            .buttonStyle(.game).frame(minWidth: 72, minHeight: 40)
                            .disabled(!enabled || session.companions.profiles.count >= 9)
                    }
                }
                HStack(spacing: 4) {
                    Button("Details") { equipmentProfile = selected }.disabled(!enabled || row == nil)
                    Button("Refresh") { session.companionCommand("list") }.disabled(session.companions.pending)
                    Button("Create Party") { session.companionCommand("party") }.disabled(!enabled || !session.party.members.isEmpty)
                    Button("Release…") { confirmRelease = row?.id }.disabled(!enabled || row == nil || row?.active == true)
                }.buttonStyle(.game).frame(minHeight: 36)
                Text(verbatim: session.companions.message).font(.game(size: 10))
                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: 36)
            }.padding(.horizontal, 8).padding(.top, 4)
        }
        .allowsHitTesting(equipmentProfile == nil)
        .overlay {
            if let id = equipmentProfile { CompanionEquipmentView(profileID: id, close: { equipmentProfile = nil }) }
        }
        .overlay {
            if let id = confirmRelease {
                ClassicGamePanel(title: "Release Companion", width: 310, height: 150, onClose: { confirmRelease = nil }) {
                    VStack(spacing: 12) {
                        Text("Permanently release this companion?\nIts level and EXP will be lost.")
                            .font(.game(size: 12)).multilineTextAlignment(.center)
                        HStack {
                            Button("OK") { session.companionCommand("retire \(id) confirm"); confirmRelease = nil }
                            Button("Cancel") { confirmRelease = nil }
                        }.buttonStyle(.game).frame(minHeight: 44)
                    }
                }
            }
        }
        .task {
            session.companionCommand("list")
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
                if session.companions.ready && session.companions.available && !session.companions.pending && confirmRelease == nil && equipmentProfile == nil { session.companionCommand("list") }
            }
        }
        .onChange(of: session.companions.profiles) {
            if let selected, !session.companions.profiles.contains(where: { $0.id == selected }) { self.selected = nil }
        }
    }
    private func action(_ title: String, verb: String, disabled: Bool) -> some View {
        Button(title) { if let selected { session.companionCommand("\(verb) \(selected)") } }
            .buttonStyle(.game).frame(minWidth: 78, minHeight: 40).disabled(!enabled || disabled)
    }
}
