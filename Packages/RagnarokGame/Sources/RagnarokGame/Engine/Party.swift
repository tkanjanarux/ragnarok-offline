import Foundation
import RagnarokPackets

struct PartyMember: Identifiable {
    var id: UInt32
    var characterID: UInt32
    var name: String
    var map: String
    var leader: Bool
    var offline: Bool
    var job: Int16
    var level: Int16
    var hp: Int32? = nil
    var maxHP: Int32? = nil
    var x: Int16? = nil
    var y: Int16? = nil
    var hpUpdatedAt: Date? = nil
    var dead = false

    var position: SIMD2<Int>? {
        guard !offline, let x, let y, x >= 0, y >= 0 else { return nil }
        return SIMD2(Int(x), Int(y))
    }

    static func mapKey(_ map: String) -> String {
        for suffix in [".gat", ".rsw"] where map.hasSuffix(suffix) {
            return String(map.dropLast(suffix.count))
        }
        return map
    }

    func isOnMap(_ mapName: String) -> Bool {
        !mapName.isEmpty && Self.mapKey(map) == Self.mapKey(mapName)
    }
}

/// Only server acknowledgements mutate membership. Wire leader=0 means leader.
struct PartyState {
    var currentMap = ""
    var name = ""
    var members: [PartyMember] = []
    var optionsReady = false
    var evenShare = false
    var pickupShare = false
    var distributionShare = false
    var optionsPending = false
    var shareMessage = "Waiting for party settings from server."

    mutating func receive(_ packet: any DecodablePacket, ownID: UInt32, now: Date = .now) {
        switch packet {
        case let p as PACKET_ZC_NPCACK_MAPMOVE:
            currentMap = PartyMember.mapKey(p.mapName)
            for index in members.indices {
                members[index].x = nil; members[index].y = nil
                members[index].hp = nil; members[index].maxHP = nil
                members[index].hpUpdatedAt = nil
            }
        case let p as PartyOptions:
            optionsReady = true; optionsPending = false
            evenShare = p.exp == 1
            pickupShare = p.pickup != 0; distributionShare = p.distribution != 0
            shareMessage = p.exp == 2 ? "EXP sharing unavailable: party level range is too large."
                : p.exp == 1 ? "Even Share enabled. Alive members on the same map can receive EXP."
                : "Each Take: EXP follows individual contribution."
        case let p as PACKET_ZC_NOTIFY_PLAYERCHAT:
            if p.Message.hasPrefix("Party EXP: ") { shareMessage = String(p.Message.dropFirst(11)) }

        case let p as PACKET_ZC_GROUP_LIST:
            name = p.partyName
            members = p.members.map { row in
                let old = members.first { $0.id == row.AID && $0.characterID == row.GID && $0.map == row.mapName }
                return PartyMember(id: row.AID, characterID: row.GID, name: row.playerName,
                    map: row.mapName, leader: row.leader == 0, offline: row.offline != 0,
                    job: row.class_, level: row.baseLevel,
                    hp: row.offline == 0 ? old?.hp : nil, maxHP: row.offline == 0 ? old?.maxHP : nil,
                    x: row.offline == 0 ? old?.x : nil, y: row.offline == 0 ? old?.y : nil,
                    hpUpdatedAt: row.offline == 0 ? old?.hpUpdatedAt : nil,
                    dead: row.offline == 0 ? old?.dead ?? false : false)
            }
        case let p as PACKET_ZC_ADD_MEMBER_TO_GROUP:
            name = p.partyName
            let old = members.first { $0.id == p.AID && $0.characterID == p.GID && $0.map == p.mapName }
            let m = PartyMember(id: p.AID, characterID: p.GID, name: p.playerName,
                map: p.mapName, leader: p.leader == 0, offline: p.offline != 0,
                job: p.class_, level: p.baseLevel,
                hp: p.offline == 0 ? old?.hp : nil, maxHP: p.offline == 0 ? old?.maxHP : nil,
                x: p.offline == 0 ? p.x : nil, y: p.offline == 0 ? p.y : nil,
                hpUpdatedAt: p.offline == 0 ? old?.hpUpdatedAt : nil,
                dead: p.offline == 0 ? old?.dead ?? false : false)
            if let i = members.firstIndex(where: { $0.id == p.AID }) { members[i] = m }
            else { members.append(m) }
        case let p as PACKET_ZC_NOTIFY_HP_TO_GROUPM:
            if let i = members.firstIndex(where: { $0.id == p.AID && !$0.offline }) {
                members[i].hp = p.hp >= 0 && p.maxhp > 0 ? p.hp : nil
                members[i].maxHP = p.maxhp > 0 ? p.maxhp : nil
                members[i].hpUpdatedAt = now
                if members[i].hp != nil { members[i].dead = p.hp == 0 }
            }
        case let p as PACKET_ZC_NOTIFY_POSITION_TO_GROUPM:
            if let i = members.firstIndex(where: { $0.id == UInt32(bitPattern: p.AID) && !$0.offline }) {
                if p.xPos < 0 || p.yPos < 0 {
                    members[i].x = nil; members[i].y = nil
                    members[i].hp = nil; members[i].maxHP = nil
                    members[i].hpUpdatedAt = nil
                } else if !currentMap.isEmpty {
                    members[i].map = currentMap + ".gat"
                    members[i].x = p.xPos; members[i].y = p.yPos
                }
            }
        case let p as PACKET_ZC_GROUP_ISALIVE:
            if let i = members.firstIndex(where: { $0.id == p.AID && !$0.offline }) {
                members[i].dead = p.isDead != 0
                members[i].hp = nil; members[i].maxHP = nil
                members[i].hpUpdatedAt = nil
            }
        case let p as PACKET_ZC_NOTIFY_MEMBERINFO_TO_GROUPM:
            if let i = members.firstIndex(where: { $0.id == UInt32(bitPattern: p.AID) }) {
                members[i].job = p.job; members[i].level = p.level
            }
        case let p as PACKET_ZC_DELETE_MEMBER_FROM_GROUP:
            if UInt32(bitPattern: p.AID) == ownID { self = PartyState(currentMap: currentMap) }
            else { members.removeAll { $0.id == UInt32(bitPattern: p.AID) } }
        case let p as PartyLeaderChanged:
            for i in members.indices { members[i].leader = members[i].id == p.newLeader }
        default: break
        }
    }
}
