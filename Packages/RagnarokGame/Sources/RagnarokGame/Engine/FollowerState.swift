import Foundation
import RagnarokPackets
import RagnarokModels

struct FollowerState {
    enum Kind: String, CaseIterable { case homunculus = "Homunculus", mercenary = "Mercenary" }
    enum Operation { case feed, rename, dismiss, upgrade, autoFeed }
    var visible = false
    var kind = Kind.homunculus
    var homunculusID: UInt32?
    var homunculus: PACKET_ZC_PROPERTY_HOMUN?
    var homSkills: [UInt16: PACKET_ZC_HOSKILLINFO_LIST_sub] = [:]
    var mercenary: MercenaryInfo?
    var mercSkills: [UInt16: PACKET_ZC_HOSKILLINFO_LIST_sub] = [:]
    var homAutoFeed: Bool?
    var pending: Operation?
    var pendingKind: Kind?
    var pendingSkill: UInt16?
    var requestedName: String?
    var token: UUID?
    var message: String?
    var actorID: UInt32? { kind == .homunculus ? homunculusID : mercenary?.id }
    var skills: [PACKET_ZC_HOSKILLINFO_LIST_sub] { Array((kind == .homunculus ? homSkills : mercSkills).values).sorted { $0.id < $1.id } }
    mutating func finish(_ operation: Operation, kind: Kind, message: String? = nil) {
        guard pending == operation, pendingKind == kind else { return }
        pending = nil; pendingKind = nil; token = nil; self.message = message
    }
    mutating func receive(_ p: PACKET_ZC_PROPERTY_HOMUN) {
        homunculus = p
        if pending == .rename { finish(.rename, kind: .homunculus, message: p.name == requestedName ? "Homunculus renamed." : "The server rejected this name.") }
    }
    mutating func receive(_ p: PACKET_ZC_CHANGESTATE_MER) {
        if p.state == 0 { homunculusID = p.gid; return }
        guard p.gid == homunculusID else { return }
        if p.state == 1 { homunculus?.intimacy = UInt16(clamping: p.data) }
        if p.state == 2 { homunculus?.hunger = UInt16(clamping: p.data) }
    }
    mutating func homParameter(_ p: PACKET_ZC_HO_PAR_CHANGE) {
        switch p.type {
        case 5: homunculus?.hp = UInt32(clamping: p.value)
        case 6: homunculus?.maxHp = UInt32(clamping: p.value)
        case 7: homunculus?.sp = UInt32(clamping: p.value)
        case 8: homunculus?.maxSp = UInt32(clamping: p.value)
        case 1: homunculus?.exp = Int64(clamping: p.value)
        case 11: homunculus?.level = UInt16(clamping: p.value)
        case 22: homunculus?.expNext = Int64(clamping: p.value)
        default: break
        }
    }
    mutating func mercParameter(_ p: MercenaryParameter) {
        switch p.type {
        case 5: mercenary?.hp = p.value
        case 6: mercenary?.maxHP = p.value
        case 7: mercenary?.sp = p.value
        case 8: mercenary?.maxSP = p.value
        case 189: mercenary?.kills = p.value
        case 190: mercenary?.faith = UInt16(clamping: p.value)
        default: break
        }
    }
    mutating func vanished(_ id: UInt32) {
        if homunculusID == id { homunculusID = nil; homunculus = nil; homSkills = [:]; homAutoFeed = nil; finish(.dismiss, kind: .homunculus, message: "Homunculus left the scene.") }
        if mercenary?.id == id { mercenary = nil; mercSkills = [:]; finish(.dismiss, kind: .mercenary, message: "Mercenary left the scene.") }
    }
}

extension PlaySession {
    func followerCommand(_ command: FollowerState.Operation) {
        guard !hasPendingInventoryOperation else { return }
        guard followers.pending == nil, enchant.pending == nil, !rodex.busy, !trade.active else { return }
        let kind = followers.kind
        if kind == .homunculus {
            guard followers.homunculus != nil else { return }
            guard command == .feed || command == .dismiss else { return }
            waitForFollower(command); sendFoundationPacket(FollowerRequest.homunculus(command == .feed ? 1 : 2))
        } else if command == .dismiss, followers.mercenary != nil {
            waitForFollower(command); sendFoundationPacket(FollowerRequest.dismissMercenary)
        }
    }
    func renameHomunculus(_ name: String) {
        guard followers.homunculus != nil, followers.pending == nil, followers.homunculus!.flags & 1 == 0,
              !name.isEmpty, name.utf8.count <= 23, !name.contains("\0") else { return }
        followers.requestedName = name; waitForFollower(.rename); sendFoundationPacket(FollowerRequest.renameHomunculus(name))
    }
    func setHomunculusAutoFeed(_ enabled: Bool) {
        guard followers.homunculus != nil, followers.pending == nil else { return }
        waitForFollower(.autoFeed); sendFoundationPacket(FollowerRequest.autoFeed(enabled))
    }
    func moveFollowerToSelectedTarget() {
        guard let id = followers.actorID, let target = mapScene?.selectedTarget else {
            followers.message = "Select a target in the scene first."; return
        }
        let position = target.gridPosition
        guard (0...1023).contains(position.x), (0...1023).contains(position.y) else { return }
        var packet = PACKET_CZ_REQUEST_MOVENPC(); packet.packetType = HEADER_CZ_REQUEST_MOVENPC
        packet.GID = id
        packet.PosDir = [UInt8(position.x >> 2), UInt8(((position.x & 3) << 6) | (position.y >> 4)), UInt8((position.y & 15) << 4)]
        sendFoundationPacket(packet)
    }
    func moveFollowerToOwner(attack: Bool = false) {
        guard let id = followers.actorID else { return }
        if attack {
            guard let target = mapScene?.selectedTarget, target.type == .monster, !target.isDead else { followers.message = "Select a monster first."; return }
            sendFoundationPacket(FollowerRequest.attack(id, target.objectID))
        } else { sendFoundationPacket(FollowerRequest.follow(id)) }
    }
    func useFollowerSkill(_ id: UInt16, upgrade: Bool = false) {
        guard let row = followers.skills.first(where: { $0.id == id }), let actor = followers.actorID else { return }
        if upgrade {
            guard followers.kind == .homunculus, row.upgradable != 0, (followers.homunculus?.skillPoints ?? 0) > 0, followers.pending == nil else { return }
            followers.pendingSkill = id; waitForFollower(.upgrade); sendFoundationPacket(FollowerRequest.upgrade(id)); return
        }
        var skill = SkillInfo(); skill.skillID = Int(row.id); skill.level = Int(row.level); skill.flag = Int(row.inf)
        guard skill.level > 0, !skill.isPassiveSkill else { return }
        if skill.isGroundTargetedSkill {
            guard let position = mapScene?.selectedTarget?.gridPosition ?? mapScene?.state.playerPosition else { return }
            useSkill(skillID: skill.skillID, level: skill.level, toGround: position)
        } else if skill.isSelfOnlySkill {
            useSkill(skillID: skill.skillID, level: skill.level, onTarget: actor)
        } else if let target = mapScene?.selectedTarget, target.type == .monster || skill.isSupportSkill {
            useSkill(skillID: skill.skillID, level: skill.level, onTarget: target.objectID)
        } else if skill.isSupportSkill {
            useSkill(skillID: skill.skillID, level: skill.level, onTarget: actor)
        } else { followers.message = "Select a target first." }
    }
    private func waitForFollower(_ operation: FollowerState.Operation) {
        let token = UUID(); followers.pending = operation; followers.pendingKind = followers.kind; followers.token = token; followers.message = "Waiting for the server…"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.followers.token == token else { return }
            self.followers.message = "No server response. Reconnect to refresh this window."
        }
    }
}
