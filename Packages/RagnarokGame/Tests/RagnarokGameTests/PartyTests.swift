import Testing
import Foundation
import BinaryIO
import RagnarokPackets
@testable import RagnarokGame

@Test func partyRosterLifecycle() {
    var state = PartyState()
    var roster = PACKET_ZC_GROUP_LIST()
    roster.partyName = "Test"
    var owner = PACKET_ZC_GROUP_LIST_SUB()
    owner.AID = 10; owner.GID = 20; owner.playerName = "Owner"; owner.leader = 0
    var knight = owner
    knight.AID = 95000000; knight.GID = 95000000; knight.playerName = "Knight"; knight.leader = 1
    knight.class_ = 7; knight.baseLevel = 10
    roster.members = [owner, knight]
    state.receive(roster, ownID: 10)
    #expect(state.members.count == 2 && state.members[0].leader && !state.members[1].leader)
    var hp = PACKET_ZC_NOTIFY_HP_TO_GROUPM()
    hp.AID = knight.AID; hp.hp = 50; hp.maxhp = 100
    state.receive(hp, ownID: 10)
    state.receive(roster, ownID: 10)
    #expect(state.members[1].hp == 50)
    roster.members[1].offline = 1
    state.receive(roster, ownID: 10)
    #expect(state.members[1].hp == nil)
    var leave = PACKET_ZC_DELETE_MEMBER_FROM_GROUP()
    leave.AID = Int32(knight.AID)
    state.receive(leave, ownID: 10)
    #expect(state.members.count == 1)
    state.receive(leave, ownID: 10)
    #expect(state.members.count == 1)
    leave.AID = 10
    state.receive(leave, ownID: 10)
    #expect(state.members.isEmpty && state.name.isEmpty)
}

@Test func partyOptionsFollowServerAndRejectUnavailableShare() throws {
    var state = PartyState()
    func response(_ exp: UInt8) throws -> PartyOptions {
        let stream = MemoryStream(data: Data([0xd8,7,exp,0,0,0,1,0]))
        return try PartyOptions(from: BinaryDecoder(stream: stream))
    }
    state.optionsPending = true
    state.receive(try response(1), ownID: 10)
    #expect(state.optionsReady && state.evenShare && !state.optionsPending && state.pickupShare)
    state.receive(try response(2), ownID: 10)
    #expect(!state.evenShare && state.shareMessage.contains("unavailable"))
    var reason = PACKET_ZC_NOTIFY_PLAYERCHAT()
    reason.Message = "Party EXP: Level difference 20 exceeds limit 15."
    state.receive(reason, ownID: 10)
    #expect(state.shareMessage == "Level difference 20 exceeds limit 15.")
    state.receive(try response(0), ownID: 10)
    #expect(!state.evenShare && state.shareMessage.contains("Each Take"))
}
