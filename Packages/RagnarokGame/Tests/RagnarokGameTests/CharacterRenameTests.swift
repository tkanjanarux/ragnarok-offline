import Testing
@testable import RagnarokGame

@Test func renameNeedsCreditAndValidUTF8ByteLength() {
    var state = CharacterRenameState()
    let beginResult1 = !state.begin(characterID: 12, credits: 0, name: "NewName")
    #expect(beginResult1)
    let beginResult2 = !state.begin(characterID: 12, credits: 1, name: "bad\0name")
    #expect(beginResult2)
    let beginResult3 = !state.begin(characterID: 12, credits: 1, name: String(repeating: "ก", count: 8))
    #expect(beginResult3)
    let beginResult4 = state.begin(characterID: 12, credits: 1, name: "  NewName  ")
    #expect(beginResult4)
    #expect(state.requestedName == "NewName")
    let beginResult5 = !state.begin(characterID: 13, credits: 1, name: "Other")
    #expect(beginResult5)
}

@Test func renameOnlyCompletesFromAckAndFreshAuthoritativeList() {
    var state = CharacterRenameState()
    _ = state.begin(characterID: 12, credits: 1, name: "NewName")
    state.receiveCharacterList([12: "OldName"])
    #expect(state.blocked)
    state.receive(result: 0)
    #expect(state.awaitingList && state.blocked)
    state.receiveCharacterList([13: "Other"])
    #expect(state.blocked)
    state.receiveCharacterList([12: "NewName"])
    #expect(!state.blocked)
    #expect(state.message == "Character renamed to NewName.")
}

@Test func renameRejectAllowsEditButTimeoutDoesNotRetryOrAcceptLateResult() {
    var state = CharacterRenameState()
    _ = state.begin(characterID: 12, credits: 1, name: "TakenName")
    state.receive(result: 4)
    #expect(!state.blocked && state.message?.contains("credit was kept") == true)
    _ = state.begin(characterID: 12, credits: 1, name: "NewName")
    state.timeout()
    state.receive(result: 0)
    state.receiveCharacterList([12: "NewName"])
    #expect(state.uncertain && state.blocked)
    let beginResult6 = !state.begin(characterID: 12, credits: 1, name: "AnotherName")
    #expect(beginResult6)
    state = CharacterRenameState() // fresh char connection, not a guessed retry
    #expect(!state.blocked)
}
