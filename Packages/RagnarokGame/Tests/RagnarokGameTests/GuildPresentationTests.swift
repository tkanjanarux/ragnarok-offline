import Testing
import Foundation
import RagnarokPackets
@testable import RagnarokGame

struct GuildPresentationTests {
    private func roster() -> GuildState {
        var state = GuildState(); state.id = 10; state.master = true
        var a = GUILD_MEMBER_INFO(); a.AID = 11; a.GID = 101; a.char_name = "Same"; a.positionID = 0
        var b = a; b.AID = 12; b.GID = 102; b.positionID = 1; b.currentState = 1
        var c = b; c.AID = 13; c.GID = 103
        state.members = [a,b,c].map { .init(data: $0) }
        state.positionNames = [0: "Master", 1: "Member", 2: "Recruit"]
        return state
    }
    @Test func stableOnlineOrderingPreservesServerOrderAndIdentity() {
        var s = roster()
        #expect(GuildPresentation.orderedMembers(s).map(\.id) == ["12:102", "13:103", "11:101"])
        #expect(s.members.map(\.id) == ["11:101", "12:102", "13:103"])
        s.members[1].data.currentState = 0
        #expect(GuildPresentation.orderedMembers(s).map(\.id) == ["13:103", "11:101", "12:102"])
        #expect(GuildPresentation.member("12:102", in: s)?.data.GID == 102)
        #expect(GuildPresentation.member("12:103", in: s) == nil)
    }
    @Test func rolePermissionsAndPendingDisableDestructiveActions() {
        var s = roster()
        #expect(!GuildPresentation.canExpel("11:101", in: s, ownCharacter: 103))
        #expect(!GuildPresentation.canExpel("12:102", in: s, ownCharacter: 102))
        #expect(GuildPresentation.canExpel("12:102", in: s, ownCharacter: 101))
        s.master = false; s.permissions = 1
        #expect(!GuildPresentation.canExpel("12:102", in: s, ownCharacter: 101))
        s.permissions = 16
        #expect(GuildPresentation.canExpel("12:102", in: s, ownCharacter: 101))
        #expect(!GuildPresentation.canAssign("12:102", position: 2, in: s, ownCharacter: 101))
        s.pending = .remove
        #expect(!GuildPresentation.canExpel("12:102", in: s, ownCharacter: 101))
    }
    @Test func selectedMemberMustStillExistAndRankMustBeCurrent() {
        var s = roster()
        #expect(GuildPresentation.canAssign("12:102", position: 2, in: s, ownCharacter: 101))
        #expect(!GuildPresentation.canAssign("12:102", position: 1, in: s, ownCharacter: 101))
        #expect(!GuildPresentation.canAssign("12:102", position: 99, in: s, ownCharacter: 101))
        #expect(!GuildPresentation.canAssign("11:101", position: 1, in: s, ownCharacter: 101))
        s.remove(characterID: 102, ownID: 101)
        #expect(!GuildPresentation.canAssign("12:102", position: 2, in: s, ownCharacter: 101))
        #expect(!GuildPresentation.canExpel("12:102", in: s, ownCharacter: 101))
    }
    @Test func confirmationsCannotCrossGuildOrPendingBoundary() {
        var s = roster()
        #expect(GuildPresentation.sameContext(10, state: s))
        #expect(!GuildPresentation.sameContext(nil, state: s))
        s.pending = .notice
        #expect(!GuildPresentation.sameContext(10, state: s))
        s.finish(.invite)
        #expect(!GuildPresentation.sameContext(10, state: s))
        s.finish(.notice)
        #expect(GuildPresentation.sameContext(10, state: s))
        s.id = 20
        #expect(!GuildPresentation.sameContext(10, state: s))
        s = GuildState()
        #expect(!GuildPresentation.sameContext(10, state: s))
        #expect(GuildPresentation.sameContext(nil, state: s))
    }
    @Test func serverAuthoritativeRankRemainsUntilAcknowledged() {
        var s = roster(); s.pending = .memberPosition
        #expect(GuildPresentation.member("12:102", in: s)?.data.positionID == 1)
        #expect(!GuildPresentation.canAssign("12:102", position: 2, in: s, ownCharacter: 101))
        s.members[1].data.positionID = 2; s.finish(.memberPosition)
        #expect(!GuildPresentation.canAssign("12:102", position: 2, in: s, ownCharacter: 101))
        #expect(GuildPresentation.canAssign("12:102", position: 1, in: s, ownCharacter: 101))
    }
    @Test func textValidationUsesWireBytesNotCharacterCount() {
        #expect(GuildPresentation.validText("กิลด์", bytes: 23, required: true))
        #expect(!GuildPresentation.validText(String(repeating: "ก", count: 8), bytes: 23, required: true))
        #expect(!GuildPresentation.validText("a\0b", bytes: 23))
        #expect(!GuildPresentation.validText("   ", bytes: 23, required: true))
        #expect(GuildPresentation.validText("", bytes: 39))
        #expect(!GuildPresentation.validText(String(repeating: "x", count: 40), bytes: 39))
    }
}
