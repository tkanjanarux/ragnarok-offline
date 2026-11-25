import SwiftUI
import UniformTypeIdentifiers

struct GuildView: View {
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var importingEmblem = false
    @State private var skillToLearn: UInt16?
    @State private var relationToRemove: Int32?
    @State private var name = ""
    @State private var reason = ""
    @State private var subject = ""
    @State private var notice = ""
    @State private var member: GuildState.Member?
    @State private var position: Int32 = 1
    @State private var editingPosition: Int32?
    @State private var confirming = ""
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: "Guild", width: min(500, bounds.size.width - 24), height: min(650, bounds.size.height - 24), onClose: { session.guild.visible = false }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let invitation = session.guild.invitation {
                            Text("Join \(invitation.guild_name)?")
                            HStack {
                                Button("Accept") { session.replyGuild(true) }
                                Button("Decline") { session.replyGuild(false) }
                            }.frame(minHeight: 44)
                        }
                        Button("Refresh") { session.openGuild() }.frame(minHeight: 44)
                        if session.guild.id == nil {
                            Text("You are not in a guild.")
                            TextField("Guild name", text: $name).textFieldStyle(.roundedBorder)
                            Text("Creating a guild requires Emperium.")
                            Button("Create guild") { confirming = "create" }.frame(minHeight: 44).disabled(name.isEmpty || session.guild.pending != nil)
                        } else {
                            Text(session.guild.name).fontWeight(.bold)
                            if let info = session.guild.info {
                                Text("Lv. \(info.level) · Members \(info.userNum)/\(info.maxUserNum)")
                                Text("Master: \(info.masterName)")
                                Text("EXP \(info.exp)/\(info.maxExp)")
                            }
                            Text(session.guild.subject).fontWeight(.bold)
                            Text(session.guild.notice)
                            Button("Refresh") { session.openGuild() }.frame(minHeight: 44)
                            guildDetails
                            members
                            if session.guild.canInvite {
                                TextField("Character name", text: $name).textFieldStyle(.roundedBorder)
                                Button("Invite") { session.inviteGuild(name) }.frame(minHeight: 44).disabled(name.isEmpty || session.guild.pending != nil)
                            }
                            if session.guild.master { management }
                            else { Button("Leave guild") { confirming = "leave" }.frame(minHeight: 44).disabled(session.guild.pending != nil) }
                        }
                        if let message = session.guild.message { Text(message) }
                    }.padding(12)
                }.font(.game(size: 13)).buttonStyle(.game)
            }
        }
        .fileImporter(isPresented: $importingEmblem, allowedContentTypes: [.bmp]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1782 else {
                    session.guild.message = "Choose a 24 × 24 BMP emblem, up to 1782 bytes."; return
                }
                session.uploadGuildEmblem(try Data(contentsOf: url))
            } catch { session.guild.message = "The emblem file could not be opened." }
        }
        .onAppear { subject = session.guild.subject; notice = session.guild.notice }
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { !confirming.isEmpty }, set: { if !$0 { confirming = "" } })) {
            Button("Confirm") {
                switch confirming {
                case "skill": if let skillToLearn { session.upgradeGuildSkill(skillToLearn) }
                case "relation": if let relationToRemove { session.removeGuildRelation(relationToRemove) }
                case "alliance": session.requestGuildAlliance()
                case "create": session.createGuild(name)
                case "leave": session.removeGuildMember(nil, reason: reason)
                case "kick": if let member { session.removeGuildMember(member, reason: reason) }
                case "position": if let member { session.setGuildMemberPosition(member, position: position) }
                case "disband": session.disbandGuild(name)
                default: break
                }
                confirming = ""
            }
            Button("Cancel", role: .cancel) { confirming = "" }
        }
        .sheet(isPresented: Binding(get: { editingPosition != nil }, set: { if !$0 { editingPosition = nil } })) {
            if let id = editingPosition { GuildPositionEditor(positionID: id) { editingPosition = nil } }
        }
    }
    private var confirmationTitle: String {
        switch confirming {
        case "skill": "Spend one guild skill point?"
        case "relation": "Remove this guild relationship?"
        case "alliance": "Send an alliance invitation to the selected guild master?"
        case "create": "Create this guild and consume Emperium?"
        case "leave": "Leave this guild?"
        case "kick": "Expel \(member?.data.char_name ?? "member")?"
        case "position": position == 0 ? "Transfer guild leadership to \(member?.data.char_name ?? "member")?" : "Change this member's position?"
        case "disband": "Permanently disband this guild?"
        default: "Confirm guild change?"
        }
    }
    @ViewBuilder private var guildDetails: some View {
        DisclosureGroup("Emblem") {
            if let bitmap = session.guild.emblemBitmap, let image = UIImage(data: bitmap) {
                Image(uiImage: image).resizable().interpolation(.none).frame(width: 48, height: 48)
            } else { Text("No emblem loaded.") }
            if session.guild.master {
                Button("Choose BMP emblem") { importingEmblem = true }.frame(minHeight: 44).disabled(session.guild.pending != nil)
                Text("24 × 24 pixels · BMP · 8-bit or 24-bit")
            }
        }
        DisclosureGroup("Guild skills (\(session.guild.skillPoints) points)") {
            ForEach(session.guild.skills.keys.sorted(), id: \.self) { id in
                if let skill = session.guild.skills[id] {
                    HStack {
                        Text("\(context.skillInfoTable.localizedSkillName(forSkillID: Int(id)) ?? "Skill \(id)") · Lv. \(skill.level)")
                        Spacer()
                        if session.guild.master && skill.level > 0 && skill.inf != 0 {
                            Button("Use") { session.useGuildSkill(id) }.frame(minHeight: 44).disabled(session.guild.pending != nil)
                        }
                        if session.guild.master && skill.upFlag == 1 {
                            Button("Learn") { skillToLearn = id; confirming = "skill" }.frame(minHeight: 44)
                                .disabled(session.guild.pending != nil || session.guild.skillPoints <= 0)
                        }
                    }
                }
            }
        }
        DisclosureGroup("Alliances and opposition") {
            if let invitation = session.guild.allianceInvitation {
                Text("Alliance invitation: \(invitation.inviterGuildName)")
                HStack {
                    Button("Accept") { session.replyGuildAlliance(true) }
                    Button("Decline") { session.replyGuildAlliance(false) }
                }.frame(minHeight: 44).disabled(session.guild.pending != nil)
            }
            if session.guild.relations.isEmpty { Text("No guild relationships.") }
            ForEach(session.guild.relations, id: \.GDID) { relation in
                HStack {
                    Text("\(relation.guildname) · \(relation.relation == 0 ? "Ally" : "Enemy")")
                    if session.guild.master {
                        Button("Remove") { relationToRemove = relation.GDID; confirming = "relation" }
                            .frame(minHeight: 44).disabled(session.guild.pending != nil)
                    }
                }
            }
            if session.guild.master {
                Button("Invite selected guild master") { confirming = "alliance" }.frame(minHeight: 44).disabled(session.guild.pending != nil)
            }
        }
    }
    @ViewBuilder private var members: some View {
        DisclosureGroup("Members") {
            ForEach(session.guild.members.sorted { $0.data.currentState > $1.data.currentState }) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(entry.data.char_name) · Lv. \(entry.data.level)")
                    Text((entry.data.currentState != 0 ? "Online" : "Offline") + " · " + (session.guild.positionNames[entry.data.positionID] ?? "Position \(entry.data.positionID)"))
                    if entry.data.GID != session.character.charID {
                        HStack {
                            if session.guild.canExpel && entry.data.positionID != 0 {
                                Button("Expel") { member = entry; confirming = "kick" }
                            }
                            if session.guild.master {
                                Menu("Position") {
                                    ForEach(session.guild.positionNames.keys.sorted(), id: \.self) { id in
                                        Button(session.guild.positionNames[id] ?? "Position \(id)") { member = entry; position = id; confirming = "position" }
                                    }
                                }
                            }
                        }.frame(minHeight: 44).disabled(session.guild.pending != nil)
                    }
                }
                Divider()
            }
        }
        TextField("Reason for leaving or expelling (optional)", text: $reason).textFieldStyle(.roundedBorder)
    }
    @ViewBuilder private var management: some View {
        DisclosureGroup("Guild notice") {
            TextField("Subject", text: $subject).textFieldStyle(.roundedBorder)
            TextField("Notice", text: $notice, axis: .vertical).textFieldStyle(.roundedBorder)
            Button("Save notice") { session.setGuildNotice(title: subject, text: notice) }.frame(minHeight: 44).disabled(session.guild.pending != nil)
        }
        DisclosureGroup("Positions and permissions") {
            ForEach(session.guild.positions.keys.sorted(), id: \.self) { id in
                Button(session.guild.positionNames[id] ?? "Position \(id)") { editingPosition = id }.frame(minHeight: 44)
            }
        }
        DisclosureGroup("Disband guild") {
            TextField("Type guild name to confirm", text: $name).textFieldStyle(.roundedBorder)
            Button("Disband") { confirming = "disband" }.frame(minHeight: 44).disabled(name != session.guild.name || session.guild.pending != nil)
        }
    }
}

struct GuildPositionEditor: View {
    let positionID: Int32
    let close: () -> Void
    @Environment(PlaySession.self) private var session
    @State private var name = ""
    @State private var tax = 0
    @State private var invite = false
    @State private var expel = false
    @State private var storage = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Guild position").fontWeight(.bold)
                TextField("Position name", text: $name).textFieldStyle(.roundedBorder)
                Stepper("EXP tax: \(tax)%", value: $tax, in: 0...100)
                Toggle("Invite members", isOn: $invite)
                Toggle("Expel members", isOn: $expel)
                Toggle("Guild storage", isOn: $storage)
                Button("Save") { session.setGuildPosition(id: positionID, name: name, tax: Int32(tax), invite: invite, expel: expel, storage: storage); close() }
                    .frame(minHeight: 44).disabled(!session.guild.master || session.guild.pending != nil)
                Button("Cancel", action: close).frame(minHeight: 44)
            }.padding(20).font(.game(size: 14)).buttonStyle(.game)
        }.onAppear {
            name = session.guild.positionNames[positionID] ?? ""
            if let p = session.guild.positions[positionID] {
                tax = Int(p.payRate); invite = p.right & 1 != 0; expel = p.right & 16 != 0; storage = p.right & 256 != 0
            }
        }
    }
}
