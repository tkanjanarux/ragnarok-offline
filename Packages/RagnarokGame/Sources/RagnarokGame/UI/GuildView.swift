import RagnarokConstants
import SwiftUI
import UniformTypeIdentifiers

struct GuildView: View {
    private enum Page: String, CaseIterable { case info = "Guild Info", members = "Members", positions = "Position", skills = "Guild Skill", notice = "Guild Notice" }
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var page: Page = .info
    @State private var importingEmblem = false
    @State private var skillToLearn: UInt16?
    @State private var relationToRemove: Int32?
    @State private var name = ""
    @State private var disbandName = ""
    @State private var reason = ""
    @State private var subject = ""
    @State private var notice = ""
    @State private var noticeDirty = false
    @State private var selectedMember: String?
    @State private var position: Int32 = 1
    @State private var editingPosition: Int32?
    @State private var confirming = ""
    @State private var confirmationGuild: UInt32?
    private var busy: Bool { session.guild.pending != nil }
    private var member: GuildState.Member? { GuildPresentation.member(selectedMember, in: session.guild) }

    var body: some View {
        GeometryReader { bounds in
            OriginalROPanel(title: "Guild", width: min(400, bounds.size.width - 16),
                            height: min(session.guild.id == nil ? 230 : 390, bounds.size.height - 16), onClose: { session.guild.visible = false }) {
                VStack(spacing: 0) {
                    if session.guild.id != nil {
                        ROTabs(choices: Page.allCases.map { ($0, $0.rawValue) }, selection: $page)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            invitations
                            if session.guild.id == nil { guildless }
                            else if let editingPosition, page == .positions, session.guild.master {
                                GuildPositionEditor(positionID: editingPosition) { self.editingPosition = nil }
                                    .id("\(session.guild.id ?? 0):\(editingPosition)")
                            } else { selectedPage }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .topLeading)
                    }.scrollDismissesKeyboard(.interactively)
                    footer
                }.textFieldStyle(ROTextFieldStyle())
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
                guard GuildPresentation.sameContext(confirmationGuild, state: session.guild), session.guild.master else { return }
                session.uploadGuildEmblem(try Data(contentsOf: url))
            } catch { session.guild.message = "The emblem file could not be opened." }
        }
        .onAppear { loadNotice() }
        .onChange(of: session.guild.subject) { _, _ in if !noticeDirty { loadNotice() } }
        .onChange(of: session.guild.notice) { _, _ in if !noticeDirty { loadNotice() } }
        .onChange(of: session.guild.id) { _, _ in clearDrafts() }
        .onChange(of: session.guild.master) { _, _ in confirming = ""; editingPosition = nil; noticeDirty = false; loadNotice() }
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { !confirming.isEmpty }, set: { if !$0 { confirming = "" } })) {
            Button("Confirm") { performConfirmedAction() }.disabled(busy)
            Button("Cancel", role: .cancel) { confirming = "" }
        }
    }

    @ViewBuilder private var selectedPage: some View {
        switch page {
        case .info: infoPage
        case .members: membersPage
        case .positions: positionsPage
        case .skills: skillsPage
        case .notice: noticePage
        }
    }
    @ViewBuilder private var invitations: some View {
        if let invitation = session.guild.invitation {
            Text("Join \(invitation.guild_name)?")
            HStack { Button("Accept") { session.replyGuild(true) }; Button("Decline") { session.replyGuild(false) } }.disabled(busy)
        }
        if let invitation = session.guild.allianceInvitation, session.guild.master {
            Text("Alliance invitation: \(invitation.inviterGuildName)")
            HStack { Button("Accept") { session.replyGuildAlliance(true) }; Button("Decline") { session.replyGuildAlliance(false) } }.disabled(busy)
        }
    }
    private var guildless: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Create Guild")
            Text("You are not in a guild.")
            TextField("Guild name", text: $name)
            Text("Creating a guild requires Emperium.")
            Button("Create guild") { ask("create") }.disabled(busy || !GuildPresentation.validText(name, bytes: 23, required: true))
        }
    }
    private var infoPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.guild.name).fontWeight(.bold)
                    if let info = session.guild.info {
                        Text("Guild lvl: \(info.level)")
                        Text("Guild Master: \(info.masterName)")
                        Text("Guildsmen: \(info.userNum) / \(info.maxUserNum)")
                        Text("Avg. level: \(info.userAverageLevel)")
                        if !info.manageLand.isEmpty { Text("Territory: \(info.manageLand)") }
                        Text("EXP: \(info.exp) / \(info.maxExp)")
                        ROProgress(value: Double(info.exp), total: Double(info.maxExp))
                    } else { Text("Waiting for guild information…") }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 5) {
                    Text("Emblem")
                    if let bitmap = session.guild.emblemBitmap, let image = UIImage(data: bitmap) {
                        Image(uiImage: image).resizable().interpolation(.none).frame(width: 24, height: 24).padding(7)
                    } else { Text("—").frame(width: 38, height: 38).accessibilityLabel("No emblem loaded") }
                    if session.guild.master {
                        Button("Edit") { confirmationGuild = session.guild.id; importingEmblem = true }.disabled(busy)
                    }
                }.frame(width: 64)
            }
            relations
            if session.guild.master {
                section("Disband guild")
                TextField("Type guild name to confirm", text: $disbandName)
                Button("Disband") { ask("disband") }.disabled(busy || disbandName != session.guild.name)
            }
        }
    }
    private var relations: some View {
        VStack(alignment: .leading, spacing: 5) {
            section("Alliance / Antagonist")
            if session.guild.relations.isEmpty { Text("No guild relationships.") }
            ForEach(session.guild.relations, id: \.GDID) { relation in
                HStack {
                    Text(relation.guildname).frame(maxWidth: .infinity, alignment: .leading)
                    Text(relation.relation == 0 ? "Ally" : "Enemy")
                    if session.guild.master {
                        Button("Remove") { relationToRemove = relation.GDID; ask("relation") }.disabled(busy)
                    }
                }
            }
            if session.guild.master { Button("Invite selected guild master") { ask("alliance") }.disabled(busy) }
        }
    }
    private var membersPage: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        cell("Name", width: 145); cell("Position", width: 110); cell("Job", width: 110); cell("Level", width: 44); cell("Tax", width: 40); cell("Contribution", width: 100)
                    }.padding(4).background(Color(white: 0.86))
                    ForEach(GuildPresentation.orderedMembers(session.guild)) { entry in
                        Button { selectedMember = entry.id } label: {
                            HStack(spacing: 6) {
                                HStack(spacing: 4) {
                                    if entry.data.currentState != 0 { GameImage("basic_interface/grp_online.bmp").frame(width: 10, height: 10) }
                                    Text(entry.data.char_name).lineLimit(1)
                                }.frame(width: 145, alignment: .leading)
                                Text(session.guild.positionNames[entry.data.positionID] ?? "—").lineLimit(1).frame(width: 110, alignment: .leading)
                                Text(jobName(entry.data.job)).lineLimit(1).frame(width: 110, alignment: .leading)
                                Text("\(entry.data.level)").frame(width: 44, alignment: .leading)
                                Text(session.guild.positions[entry.data.positionID].map { "\($0.payRate)%" } ?? "—").frame(width: 40, alignment: .leading)
                                Text("\(entry.data.contributionExp)").frame(width: 100, alignment: .leading)
                            }.padding(4).frame(minHeight: 32).background(selectedMember == entry.id ? Color.blue.opacity(0.13) : Color.white.opacity(0.7)).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(entry.data.char_name), \(entry.data.currentState != 0 ? "Online" : "Offline")")
                    }
                }
            }
            if session.guild.members.isEmpty { Text("No member information received.") }
            if let member {
                Text(member.data.char_name).fontWeight(.bold)
                Text(member.data.currentState != 0 ? "Online" : "Offline")
                if session.guild.master && member.data.GID != session.character.charID {
                    Menu {
                        ForEach(session.guild.positionNames.keys.sorted(), id: \.self) { id in
                            Button(session.guild.positionNames[id] ?? "Position \(id)") { position = id; ask("position") }
                                .disabled(!GuildPresentation.canAssign(selectedMember, position: id, in: session.guild, ownCharacter: session.character.charID))
                        }
                    } label: { Text("Change position").frame(minHeight: 30) }.disabled(busy)
                }
                if GuildPresentation.canExpel(selectedMember, in: session.guild, ownCharacter: session.character.charID) {
                    Button("Expel") { ask("kick") }.disabled(!GuildPresentation.validText(reason, bytes: 39))
                }
            }
            if session.guild.canExpel || !session.guild.master {
                TextField("Reason (optional)", text: $reason)
            }
            if session.guild.canInvite {
                HStack {
                    TextField("Character name", text: $name)
                    Button("Invite") { session.inviteGuild(name) }.disabled(busy || !GuildPresentation.validText(name, bytes: 23, required: true))
                }
            }
            if !session.guild.master {
                Button("Leave guild") { ask("leave") }.disabled(busy || !GuildPresentation.validText(reason, bytes: 39))
            }
        }
    }
    private var positionsPage: some View {
        VStack(alignment: .leading, spacing: 5) {
            section("Positions and permissions")
            if session.guild.positions.isEmpty { Text("No position information received.") }
            ForEach(session.guild.positions.keys.sorted(), id: \.self) { id in
                if let p = session.guild.positions[id] {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(id + 1)").frame(width: 20)
                            Text(session.guild.positionNames[id] ?? "—").frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(p.payRate)%")
                            if session.guild.master { Button("Edit") { editingPosition = id }.disabled(busy) }
                        }
                        HStack(spacing: 10) {
                            permission("Invite", enabled: p.right & 1 != 0)
                            permission("Expel", enabled: p.right & 16 != 0)
                            permission("Storage", enabled: p.right & 256 != 0)
                        }
                    }.padding(4).background(Color.white.opacity(0.7))
                }
            }
        }
    }
    private var skillsPage: some View {
        VStack(alignment: .leading, spacing: 5) {
            section("Guild skills (\(session.guild.skillPoints) points)")
            if session.guild.skills.isEmpty { Text("No guild skill information received.") }
            ForEach(session.guild.skills.keys.sorted(), id: \.self) { id in
                if let skill = session.guild.skills[id] {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(context.skillInfoTable.localizedSkillName(forSkillID: Int(id)) ?? "Skill \(id)")
                            Text("Lv. \(skill.level)")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if session.guild.master && skill.level > 0 && skill.inf != 0 {
                            Button("Use") { session.useGuildSkill(id) }.disabled(busy)
                        }
                        if session.guild.master && skill.upFlag == 1 {
                            Button { skillToLearn = id; ask("skill") } label: {
                                GameImage("basic_interface/skill_up_a.bmp").frame(width: 30, height: 30).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Learn \(context.skillInfoTable.localizedSkillName(forSkillID: Int(id)) ?? "Skill \(id)")")
                                .disabled(busy || session.guild.skillPoints <= 0)
                        }
                    }.padding(4).background(Color.white.opacity(0.7))
                }
            }
        }
    }
    private var noticePage: some View {
        VStack(alignment: .leading, spacing: 6) {
            section("Guild Notice")
            if session.guild.master {
                TextField("Subject", text: Binding(get: { subject }, set: { subject = $0; noticeDirty = true }))
                TextField("Notice", text: Binding(get: { notice }, set: { notice = $0; noticeDirty = true }), axis: .vertical).lineLimit(4...8)
                Button("Save notice") {
                    session.setGuildNotice(title: subject, text: notice)
                    if session.guild.pending == .notice { noticeDirty = false }
                }.disabled(busy || !noticeDirty || !GuildPresentation.validText(subject, bytes: 59) || !GuildPresentation.validText(notice, bytes: 119))
            } else {
                Text(session.guild.subject).fontWeight(.bold)
                Text(session.guild.notice)
            }
        }
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let message = session.guild.message { Text(message).lineLimit(3).padding(.horizontal, 6) }
            HStack {
                Button("Refresh") { session.openGuild() }.disabled(busy)
                Spacer()
                Button("Close") { session.guild.visible = false }
            }.padding(.horizontal, 6)
        }.background { GameImage("basic_interface/btnbar_mid2.bmp") { $0.resizable(resizingMode: .tile) }.allowsHitTesting(false) }
    }
    private func section(_ title: String) -> some View {
        Text(LocalizedStringKey(title)).fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading).padding(4).background(Color(white: 0.88))
    }
    private func cell(_ title: String, width: CGFloat) -> some View { Text(LocalizedStringKey(title)).frame(width: width, alignment: .leading) }
    private func permission(_ title: String, enabled: Bool) -> some View {
        HStack(spacing: 3) { GameImage(enabled ? "checkbox_1.bmp" : "checkbox_0.bmp").frame(width: 13, height: 13); Text(LocalizedStringKey(title)) }.accessibilityValue(enabled ? "Yes" : "No")
    }
    private func jobName(_ job: Int16) -> String {
        guard let name = JobID(rawValue: Int(job))?.localizedName else { return "Job \(job)" }
        return String(localized: name)
    }
    private func loadNotice() { subject = session.guild.subject; notice = session.guild.notice }
    private func clearDrafts() {
        confirming = ""; selectedMember = nil; editingPosition = nil; importingEmblem = false
        name = ""; disbandName = ""; reason = ""; noticeDirty = false; page = .info; loadNotice()
    }
    private func ask(_ action: String) { confirmationGuild = session.guild.id; confirming = action }
    private func performConfirmedAction() {
        defer { confirming = "" }
        guard GuildPresentation.sameContext(confirmationGuild, state: session.guild) else { return }
        switch confirming {
        case "skill": if let skillToLearn { session.upgradeGuildSkill(skillToLearn) }
        case "relation": if let relationToRemove { session.removeGuildRelation(relationToRemove) }
        case "alliance": session.requestGuildAlliance()
        case "create": session.createGuild(name)
        case "leave": session.removeGuildMember(nil, reason: reason)
        case "kick": if let member, GuildPresentation.canExpel(selectedMember, in: session.guild, ownCharacter: session.character.charID) { session.removeGuildMember(member, reason: reason) }
        case "position": if let member, GuildPresentation.canAssign(selectedMember, position: position, in: session.guild, ownCharacter: session.character.charID) { session.setGuildMemberPosition(member, position: position) }
        case "disband": session.disbandGuild(disbandName)
        default: break
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
}

private struct GuildPositionEditor: View {
    let positionID: Int32
    let close: () -> Void
    @Environment(PlaySession.self) private var session
    @State private var name = ""
    @State private var tax = "0"
    @State private var invite = false
    @State private var expel = false
    @State private var storage = false
    @State private var submitted = false
    private var valid: Bool {
        guard let value = Int32(tax), (0...100).contains(value) else { return false }
        return GuildPresentation.validText(name, bytes: 23)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Guild position").fontWeight(.bold)
            TextField("Position name", text: $name)
            HStack { Text("EXP tax (%)"); TextField("0", text: $tax).keyboardType(.numberPad).frame(width: 65) }
            check("Invite members", value: $invite)
            check("Expel members", value: $expel)
            check("Guild storage", value: $storage)
            HStack {
                Button("Save") {
                    guard let value = Int32(tax) else { return }
                    session.setGuildPosition(id: positionID, name: name, tax: value, invite: invite, expel: expel, storage: storage)
                    submitted = session.guild.pending == .position
                }.disabled(!valid || !session.guild.master || session.guild.pending != nil || session.guild.positions[positionID] == nil)
                Button("Back", action: close)
            }
        }.onAppear { load() }
            .onChange(of: session.guild.pending) { _, pending in
                if submitted && pending == nil { submitted = false; load() }
            }
    }
    private func load() {
        name = session.guild.positionNames[positionID] ?? ""
        if let p = session.guild.positions[positionID] {
            tax = String(p.payRate); invite = p.right & 1 != 0; expel = p.right & 16 != 0; storage = p.right & 256 != 0
        }
    }
    private func check(_ title: String, value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack(spacing: 6) {
                GameImage(value.wrappedValue ? "checkbox_1.bmp" : "checkbox_0.bmp").frame(width: 13, height: 13)
                Text(LocalizedStringKey(title)); Spacer()
            }.frame(minHeight: 30).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(session.guild.pending != nil).accessibilityValue(value.wrappedValue ? "On" : "Off")
    }
}
