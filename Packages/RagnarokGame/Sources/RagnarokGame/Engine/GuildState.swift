import Foundation
import RagnarokPackets

struct GuildState {
    struct Member: Identifiable { var id: String { "\(data.AID):\(data.GID)" }; var data: GUILD_MEMBER_INFO }
    enum Operation { case create, invite, join, remove, disband, notice, memberPosition, position, skill }
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
        if id != p.guildId { info = nil; members = []; positions = [:]; positionNames = [:] }
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

extension PlaySession {
    func openGuild() {
        guild.visible = true
        sendFoundationPacket(GuildRequest.access)
        for page in 0...2 { sendFoundationPacket(GuildRequest.page(UInt32(page))) }
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
    private func waitForGuild(_ operation: GuildState.Operation) {
        let token = UUID(); guild.pending = operation; guild.token = token; guild.message = "Waiting for the server…"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, self.guild.token == token else { return }
            self.guild.message = "No server result. Reconnect to refresh guild permissions and state."
        }
    }
}
