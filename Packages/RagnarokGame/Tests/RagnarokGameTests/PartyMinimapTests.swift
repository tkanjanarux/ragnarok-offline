import Foundation
import Testing
import BinaryIO
import RagnarokPackets
@testable import RagnarokGame

@Suite struct PartyMinimapTests {

@Test func partyHealthUses32BitWireValues() throws {
    let packet = try PACKET_ZC_NOTIFY_HP_TO_GROUPM(from: BinaryDecoder(stream:
        MemoryStream(data: Data([0x0e, 0x08, 11, 0, 0, 0, 0x70, 0x11, 0x01, 0, 0xa0, 0x86, 0x01, 0]))))
    #expect(packet.AID == 11 && packet.hp == 70_000 && packet.maxhp == 100_000)
}

@Test func partyPositionWireRemovalAndIdentity() throws {
    var state = PartyState(currentMap: "prontera")
    var roster = PACKET_ZC_GROUP_LIST()
    var member = PACKET_ZC_GROUP_LIST_SUB()
    member.AID = 95_000_000; member.GID = 21; member.playerName = "Same name"; member.mapName = "prontera.gat"
    var other = member
    other.AID = 11; other.GID = 22
    roster.members = [member, other]
    state.receive(roster, ownID: 10)
    #expect(state.members.allSatisfy { $0.position == nil && $0.hp == nil })
    var position = PACKET_ZC_NOTIFY_POSITION_TO_GROUPM()
    position.AID = Int32(member.AID); position.xPos = 100; position.yPos = 200
    state.receive(position, ownID: 10)
    state.receive(roster, ownID: 10)
    #expect(state.members[0].position == SIMD2(100, 200))
    #expect(state.members[1].position == nil)
    let removal = try PACKET_ZC_NOTIFY_POSITION_TO_GROUPM(from: BinaryDecoder(stream:
        MemoryStream(data: Data([0x07, 0x01, 0xc0, 0x95, 0xa9, 0x05, 0xff, 0xff, 0xff, 0xff]))))
    #expect(removal.AID == Int32(member.AID))
    state.receive(removal, ownID: 10)
    #expect(state.members[0].position == nil)
    state.receive(position, ownID: 10)
    roster.members[0].GID = 99
    state.receive(roster, ownID: 10)
    #expect(state.members[0].position == nil)
}

@Test func partyHealthMapOfflineDeathAndLeave() {
    var state = PartyState(currentMap: "prontera")
    var roster = PACKET_ZC_GROUP_LIST()
    var member = PACKET_ZC_GROUP_LIST_SUB()
    member.AID = 11; member.GID = 21; member.mapName = "prontera.gat"
    roster.members = [member]
    state.receive(roster, ownID: 10)
    var hp = PACKET_ZC_NOTIFY_HP_TO_GROUPM()
    hp.AID = 11; hp.hp = 50; hp.maxhp = 100
    let now = Date(timeIntervalSince1970: 100)
    state.receive(hp, ownID: 10, now: now)
    #expect(state.members[0].hp == 50 && state.members[0].hpUpdatedAt == now)
    hp.hp = 0
    state.receive(hp, ownID: 10)
    #expect(state.members[0].dead)
    var alive = PACKET_ZC_GROUP_ISALIVE()
    alive.AID = 11; alive.isDead = 0
    state.receive(alive, ownID: 10)
    #expect(!state.members[0].dead && state.members[0].hp == nil)
    hp.hp = -1
    state.receive(hp, ownID: 10)
    #expect(state.members[0].hp == nil)
    var position = PACKET_ZC_NOTIFY_POSITION_TO_GROUPM()
    position.AID = 11; position.xPos = 0; position.yPos = 0
    state.receive(position, ownID: 10)
    #expect(state.members[0].position == SIMD2(0, 0))
    var warp = PACKET_ZC_NPCACK_MAPMOVE()
    warp.mapName = "geffen.gat"
    state.receive(warp, ownID: 10)
    #expect(state.members[0].position == nil && state.members[0].hp == nil)
    state.receive(position, ownID: 10)
    #expect(state.members[0].isOnMap("geffen.rsw"))
    roster.members[0].offline = 1
    state.receive(roster, ownID: 10)
    hp.hp = 70
    state.receive(hp, ownID: 10)
    state.receive(position, ownID: 10)
    #expect(state.members[0].position == nil && state.members[0].hp == nil)
    var leave = PACKET_ZC_DELETE_MEMBER_FROM_GROUP()
    leave.AID = 10
    state.receive(leave, ownID: 10)
    #expect(state.members.isEmpty && state.currentMap == "geffen")
}

@Test func minimapProjectionAxesPaddingZoomAndBounds() {
    var map = MinimapProjection(width: 400, height: 200, player: SIMD2(200, 100))
    #expect(map.point(SIMD2(0, 0)) == CGPoint(x: 0, y: 72))
    #expect(map.point(SIMD2(200, 100)) == CGPoint(x: 48, y: 48))
    #expect(map.point(SIMD2(399, 199)).y < map.point(SIMD2(0, 0)).y)
    #expect(map.contains(SIMD2(0, 0)))
    #expect(!map.contains(SIMD2(-1, -1)) && !map.contains(SIMD2(400, 200)))
    for zoom in [10, 6, 3, 2] {
        map.zoomFactor = zoom
        #expect(map.point(map.player) == CGPoint(x: 48, y: 48))
        #expect(map.point(SIMD2(210, 100)).x > 48)
        #expect(map.point(SIMD2(200, 110)).y < 48)
    }
    map.player = SIMD2(0, 0)
    #expect(abs(map.point(map.player).x) < 0.00001)
    map = MinimapProjection(width: 200, height: 400)
    #expect(map.point(SIMD2(0, 0)) == CGPoint(x: 24, y: 96))
    map = MinimapProjection(width: 0, height: 0)
    #expect(map.point(SIMD2(0, 0)).x.isFinite)
}

}
