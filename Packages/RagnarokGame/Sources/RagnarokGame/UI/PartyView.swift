import RagnarokConstants
import SwiftUI

/// roBrowser PartyFriendsV1: renewal job/crown/status icons, two-line members,
/// white list and mesbtn toolbar. Uses the same GRF assets as the game.
struct PartyView: View {
    var onClose: () -> Void
    @Environment(PlaySession.self) private var session
    @State private var selected: UInt32?
    @State private var confirmLeave = false
    @State private var confirmKick = false
    @State private var showSetup = false

    private var selectedMember: PartyMember? { session.party.members.first { $0.id == selected } }
    private var canKick: Bool {
        session.party.members.contains { $0.id == session.partyAccountID && $0.leader }
            && selectedMember != nil && selected != session.partyAccountID
    }

    var body: some View {
        ClassicGamePanel(title: "Party \(session.party.name)", width: 320, height: 278, onClose: onClose) {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.party.members) { member in
                            Button { selected = member.id } label: { memberRow(member) }
                                .buttonStyle(.plain)
                        }
                        if session.party.members.isEmpty {
                            Text("Not in a party").foregroundStyle(.secondary).padding(.top, 30)
                        }
                    }.padding(4)
                }.frame(height: 196)
                HStack(spacing: 0) {
                    toolbar("mesbtn_04", label: "Party Setup", disabled: session.party.members.isEmpty) { showSetup = true }
                    toolbar("mesbtn_05", label: "Expel from party", disabled: !canKick) { confirmKick = true }
                    toolbar("mesbtn_09", label: "Leave Party", disabled: session.party.members.isEmpty) { confirmLeave = true }
                    Spacer()
                }
                .frame(height: 44)
                .background { GameImage("basic_interface/mesbtn_mid.bmp") { $0.resizable() }.allowsHitTesting(false) }
                HStack(spacing: 4) {
                    GameImage("radiobtn_on.bmp").frame(width: 12, height: 12)
                    Text("Party")
                    Spacer()
                    Text("\(session.party.members.count)/12")
                }.padding(.horizontal, 6).frame(height: 21)
                .background { GameImage("basic_interface/btnbar_mid.bmp") { $0.resizable() }.allowsHitTesting(false) }
            }
        }
        .overlay {
            if showSetup { PartySetupView { showSetup = false } }
        }
        .confirmationDialog("Leave this party?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave Party", role: .destructive) { session.leaveParty() }
        }
        .confirmationDialog("Expel \(selectedMember?.name ?? "member")?", isPresented: $confirmKick, titleVisibility: .visible) {
            Button("Expel from party", role: .destructive) {
                if let member = selectedMember { session.expelPartyMember(member) }
            }
        }
    }

    private func toolbar(_ image: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GameImage("basic_interface/\(image).bmp")
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.4 : 1)
            .accessibilityLabel(label).help(label)
    }

    private func memberRow(_ member: PartyMember) -> some View {
        HStack(spacing: 5) {
            ZStack(alignment: .top) {
                GameImage("renewalparty/icon_jobs_\(member.job)\(member.hp == 0 ? "_die" : "").bmp")
                if member.leader { GameImage("renewalparty/ico_partycrown.bmp").offset(y: -6) }
            }.frame(width: 26, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Lv. \(member.level)")
                    Text(verbatim: member.name).fontWeight(member.leader ? .bold : .regular).lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 4) {
                    if !member.offline, let hp = member.hp, let maxHP = member.maxHP, maxHP > 0 {
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color(white: 0.3))
                            Rectangle().fill(Color.green).frame(width: 75 * CGFloat(min(hp, maxHP)) / CGFloat(maxHP))
                        }.frame(width: 75, height: 5)
                        Text("\(hp)/\(maxHP)")
                    } else { Text(member.offline ? "Offline" : member.map.replacingOccurrences(of: ".gat", with: "")) }
                    Spacer(minLength: 0)
                    Text(jobName(member.job)).lineLimit(1)
                }.font(.game(size: 10))
            }
            GameImage("renewalparty/icon_party_\(member.id == session.partyAccountID ? "me" : member.offline ? "off" : "on").bmp")
                .frame(width: 14, height: 14)
        }
        .foregroundStyle(member.offline ? Color.gray : member.leader ? Color(red: 0.03, green: 0.19, blue: 0.48) : Color(red: 0, green: 0.48, blue: 0.48))
        .padding(.horizontal, 3).frame(height: 44)
        .background(selected == member.id ? Color(red: 0.81, green: 0.88, blue: 1) : .white)
        .contentShape(Rectangle())
        .accessibilityLabel("\(member.name), level \(member.level), \(jobName(member.job))\(member.leader ? ", party leader" : "")")
    }

    private func jobName(_ job: Int16) -> String {
        guard let name = JobID(rawValue: Int(job))?.localizedName else { return "Job \(job)" }
        return String(localized: name)
    }
}
