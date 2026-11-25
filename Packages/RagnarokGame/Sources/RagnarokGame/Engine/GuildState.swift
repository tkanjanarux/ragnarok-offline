import Foundation
import RagnarokPackets

struct GuildState {
    struct Member: Identifiable { var id: String { "\(data.AID):\(data.GID)" }; var data: GUILD_MEMBER_INFO }
    enum Operation { case create, invite, join, remove, disband, notice, memberPosition, position, skill, alliance, emblem }
    var skills: [UInt16: GUILD_SKILLDATA] = [:]
    var skillPoints: Int16 = 0
    var pendingSkill: UInt16?
    var relations: [RELATED_GUILD_INFO] = []
    var allianceInvitation: PACKET_ZC_REQ_ALLY_GUILD?
    var emblemVersion: UInt32 = 0
    var emblemBitmap: Data?
    var submittedEmblem: [UInt8]?
    var visible = false
    var id: UInt32?
    var name = ""
    var master = false
    var permissions: UInt32 = 0
    var info: PACKET_ZC_GUILD_INFO?
    var members: [Member] = []
    var positionNames: [Int32: String] = [:]
    var positions: [Int32: PACKET_ZC_POSITION_INFO_sub] = [:]
    var subject = ""
    var notice = ""
    var invitation: PACKET_ZC_REQ_JOIN_GUILD?
    var pending: Operation?
    var token: UUID?
    var message: String?
    var canInvite: Bool { id != nil && (master || permissions & 1 != 0) }
    var canExpel: Bool { id != nil && (master || permissions & 16 != 0) }
    mutating func receive(_ p: PACKET_ZC_UPDATE_GDID) {
        if id != p.guildId { info = nil; members = []; positions = [:]; positionNames = [:]; skills = [:]; relations = []; emblemBitmap = nil; emblemVersion = 0; submittedEmblem = nil; allianceInvitation = nil; pending = nil; token = nil; pendingSkill = nil }
        id = p.guildId > 0 ? p.guildId : nil; name = p.guildName; master = p.isMaster != 0; permissions = p.mode
        finish(.join)
        if pending == .memberPosition { finish(.memberPosition) }
    }
    mutating func receive(_ p: PACKET_ZC_MEMBERMGR_INFO) {
        members = p.guildMemberInfo.filter { $0.AID > 0 && $0.GID > 0 }.map { .init(data: $0) }
    }
    mutating func refreshPermissions(account: UInt32, character: UInt32) {
        guard let member = members.first(where: { $0.data.AID == account && $0.data.GID == character }),
              let position = positions[member.data.positionID] else { return }
        permissions = UInt32(bitPattern: position.right)
    }
    mutating func finish(_ operation: Operation, message: String? = nil) {
        guard pending == operation else { return }
        pending = nil; token = nil; self.message = message
    }
    mutating func remove(characterID: UInt32, ownID: UInt32) {
        if characterID == ownID { let wasVisible = visible; self = GuildState(); visible = wasVisible; message = "You are no longer in this guild." }
        else { members.removeAll { $0.data.GID == characterID }; finish(.remove) }
    }
}

// Validates the actual BMP accepted by the map server; never resizes a user's image.
enum GuildBitmap {
    static func isValid(_ data: Data) -> Bool {
        let b = Array(data)
        guard (54...1782).contains(b.count), b[0] == 0x42, b[1] == 0x4d else { return false }
        func u32(_ i: Int) -> UInt32 { UInt32(b[i]) | UInt32(b[i+1]) << 8 | UInt32(b[i+2]) << 16 | UInt32(b[i+3]) << 24 }
        func u16(_ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i+1]) << 8 }
        let depth = u16(28), offset = Int(u32(10))
        guard u32(2) == UInt32(b.count), u32(14) == 40, u32(18) == 24,
              [Int32(24), -24].contains(Int32(bitPattern: u32(22))), u16(26) == 1,
              [UInt16(8), 24].contains(depth), u32(30) == 0, offset >= 54 else { return false }
        let rowSize = ((24 * Int(depth) + 31) / 32) * 4
        if depth == 8 {
            let colors = u32(46) == 0 ? 256 : Int(u32(46))
            guard (1...256).contains(colors), offset >= 54 + colors * 4 else { return false }
        }
        return offset <= b.count && b.count - offset == rowSize * 24
    }
}


extension PlaySession {
    func openGuild() {
        guild.visible = true
        sendFoundationPacket(GuildRequest.access)
        for page in 0...3 { sendFoundationPacket(GuildRequest.page(UInt32(page))) }
    }
    func upgradeGuildSkill(_ id: UInt16) {
        guard guild.master, guild.pending == nil, guild.skillPoints > 0, guild.skills[id]?.upFlag == 1 else { return }
        guild.pendingSkill = id; waitForGuild(.skill); upgradeSkillLevel(skillID: Int(id))
    }
    func requestGuildAlliance() {
        guard guild.master, guild.pending == nil else { return }
        guard let target = mapScene?.selectedTarget, target.type == .pc, target.objectID != partyAccountID else {
            guild.message = "Select the other guild master in the scene first."; return
        }
        waitForGuild(.alliance)
        sendFoundationPacket(GuildRequest.alliance(target.objectID, partyAccountID, character.charID))
    }
    func replyGuildAlliance(_ accept: Bool) {
        guard guild.master, let invitation = guild.allianceInvitation, guild.pending == nil else { return }
        guild.allianceInvitation = nil
        if accept { waitForGuild(.alliance) }
        sendFoundationPacket(GuildRequest.allianceReply(invitation.inviterId, accept))
    }
    func removeGuildRelation(_ id: Int32) {
        guard guild.master, guild.pending == nil, let row = guild.relations.first(where: { $0.GDID == id }), (0...1).contains(row.relation) else { return }
        waitForGuild(.alliance); sendFoundationPacket(GuildRequest.removeRelation(UInt32(bitPattern: id), UInt32(row.relation)))
    }
    func createGuild(_ name: String) {
        guard guild.id == nil, guild.pending == nil, !name.isEmpty, name.utf8.count <= 23, !name.contains("\0") else { return }
        waitForGuild(.create); sendFoundationPacket(GuildRequest.create(partyAccountID, name))
    }
    func inviteGuild(_ name: String) {
        guard guild.canInvite, guild.pending == nil, !name.isEmpty, name.utf8.count <= 23, !name.contains("\0") else { return }
        waitForGuild(.invite); sendFoundationPacket(GuildRequest.invite(name))
    }
    func replyGuild(_ accept: Bool) {
        guard let invitation = guild.invitation, guild.pending == nil else { return }
        guild.invitation = nil
        if accept { waitForGuild(.join) }
        sendFoundationPacket(GuildRequest.reply(invitation.guild_id, accept))
    }
    func removeGuildMember(_ member: GuildState.Member?, reason: String) {
        guard let id = guild.id, guild.pending == nil, reason.utf8.count <= 39, !reason.contains("\0") else { return }
        if let member {
            guard guild.canExpel, member.data.GID != character.charID, member.data.positionID != 0 else { return }
            sendFoundationPacket(GuildRequest.remove(guild: id, account: member.data.AID, character: member.data.GID, reason: reason, kick: true))
        } else {
            guard !guild.master else { return }
            sendFoundationPacket(GuildRequest.remove(guild: id, account: partyAccountID, character: character.charID, reason: reason, kick: false))
        }
        waitForGuild(.remove)
    }
    func disbandGuild(_ name: String) {
        guard guild.master, guild.pending == nil, name == guild.name else { return }
        waitForGuild(.disband); sendFoundationPacket(GuildRequest.disband(name))
    }
    func setGuildNotice(title: String, text: String) {
        guard guild.master, let id = guild.id, guild.pending == nil, title.utf8.count <= 59, text.utf8.count <= 119, !title.contains("\0"), !text.contains("\0") else { return }
        waitForGuild(.notice); sendFoundationPacket(GuildRequest.notice(id, title, text))
    }
    func setGuildMemberPosition(_ member: GuildState.Member, position: Int32) {
        guard guild.master, guild.pending == nil, member.data.GID != character.charID,
              guild.positionNames[position] != nil else { return }
        waitForGuild(.memberPosition); sendFoundationPacket(GuildRequest.memberPosition(member.data.AID, member.data.GID, position))
    }
    func setGuildPosition(id: Int32, name: String, tax: Int32, invite: Bool, expel: Bool, storage: Bool) {
        guard guild.master, guild.pending == nil, guild.positions[id] != nil, (0...100).contains(tax), name.utf8.count <= 23, !name.contains("\0") else { return }
        let mode: Int32 = (invite ? 1 : 0) | (expel ? 16 : 0) | (storage ? 256 : 0)
        waitForGuild(.position); sendFoundationPacket(GuildRequest.position(id, mode, tax, name))
    }
    func waitForGuild(_ operation: GuildState.Operation) {
        let token = UUID(); guild.pending = operation; guild.token = token; guild.message = "Waiting for the server…"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, self.guild.token == token else { return }
            self.guild.message = "No server result. Reconnect to refresh guild permissions and state."
        }
    }
}
