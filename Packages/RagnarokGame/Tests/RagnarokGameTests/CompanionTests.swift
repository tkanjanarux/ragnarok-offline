import Testing
@testable import RagnarokGame

@Test func companionAtomicSnapshotAndStaleResponses() {
    var s = CompanionState()
    let a = s.begin()
    s.receive("[RCO1] \(a) begin 1 1")
    s.receive("[RCO1] \(a) row 1 7 10 1 15 2 80 100 20 30 95000000 2 0 AI-Knight-1")
    #expect(s.profiles.isEmpty && s.pending)
    s.receive("[RCO1] \(a) end Summoned.")
    #expect(s.profiles.count == 1 && s.profiles[0].active && s.profiles[0].stateName == "Assisting")
    let b = s.begin()
    s.receive("[RCO1] \(a) begin 0 1")
    s.receive("[RCO1] \(a) end Stale")
    #expect(s.pending && s.profiles.count == 1)
    s.receive("[RCO1] \(b) begin 0 1"); s.receive("[RCO1] \(b) end Released.")
    #expect(!s.pending && s.profiles.isEmpty && s.ready)
}
@Test func companionRejectsPartialDuplicateAndOversizedSnapshots() {
    var s = CompanionState()
    let a = s.begin();s.receive("[RCO1] \(a) begin 1 1");s.receive("[RCO1] \(a) end missing")
    #expect(!s.ready && !s.pending)
    let b = s.begin();s.receive("[RCO1] \(b) begin 10 1")
    #expect(!s.pending)
    let c = s.begin();s.receive("[RCO1] \(c) begin 2 1")
    let row = "[RCO1] \(c) row 1 8 10 1 0 0 -1 0 -1 0 0 0 20 AI-Priest-1"
    s.receive(row);s.receive(row)
    #expect(!s.ready && s.profiles.isEmpty)
    let d = s.begin();s.receive("[RCO1] \(d) begin 0 0");s.receive("[RCO1] \(d) end Disabled.")
    #expect(s.ready && !s.available && s.message == "Disabled.")
    let handled = s.receive("ordinary server message"); #expect(!handled)
}
@Test func companionTimeoutNeverRetriesMutation() {
    var s = CompanionState();let a = s.begin();let b = s.begin()
    s.timeout(a);#expect(s.pending)
    s.timeout(b);#expect(!s.pending && !s.ready)
}

@Test func companionEquipmentSnapshotIsAtomicAndBoundToProfile() {
    var s = CompanionState(); let t = s.begin("equipment 2")
    s.receive("[RCO1] \(t) begin 1 1")
    s.receive("[RCO1] \(t) row 2 7 10 1 0 0 -1 0 -1 0 0 0 0 AI-Knight-2")
    s.receive("[RCO1] \(t) gearbegin 2 1 1 1")
    s.receive("[RCO1] \(t) gear 9 1101 2 0")
    s.receive("[RCO1] \(t) bag 4 2301 7654321")
    #expect(!s.equipmentReady && s.equipment.isEmpty)
    s.receive("[RCO1] \(t) end Waiting.")
    #expect(s.equipmentReady && s.equipmentProfile == 2 && s.transferPending && s.completedSequence == t)
    #expect(s.equipment[0].equipped && s.bag[0].uniqueID == 7654321)
    let next = s.begin("equipment 3")
    s.receive("[RCO1] \(t) gearbegin 2 0 0 0")
    #expect(s.pending && !s.equipmentReady)
    s.receive("[RCO1] \(next) begin 0 1")
    s.receive("[RCO1] \(next) gearbegin 2 0 0 0")
    #expect(!s.ready && !s.pending)
}
@Test func companionEquipmentRejectsPartialAndDuplicateBag() {
    for duplicate in [false, true] {
        var s = CompanionState();let t = s.begin("equipment 2")
        s.receive("[RCO1] \(t) begin 1 1")
        s.receive("[RCO1] \(t) row 2 7 10 1 0 0 -1 0 -1 0 0 0 0 AI-Knight-2")
        s.receive("[RCO1] \(t) gearbegin 2 0 2 0")
        s.receive("[RCO1] \(t) bag 4 1101 123")
        if duplicate { s.receive("[RCO1] \(t) bag 5 1101 123") }
        s.receive("[RCO1] \(t) end Ready.")
        #expect(!s.equipmentReady && !s.ready && !s.pending)
    }
}

@Test func companionDetailsAndSupplySnapshots() {
    var s = CompanionState(); let n = s.begin("inspect 1")
    let frames = ["begin 1 1", "row 1 8 26 29 0 0 80 100 20 30 95000000 2 19 AI-Priest-1",
                  "gearbegin 1 0 0 0", "detailbegin 1 2 1 1 1 8 1",
                  "starter 0 1601 1", "starter 1 2301 1", "skill 54 1 4 20 30 5",
                  "supply 505 10", "supplybag 2 505 20"]
    for f in frames { s.receive("[RCO1] \(n) \(f)") }
    #expect(!s.detailReady && s.profiles.isEmpty)
    s.receive("[RCO1] \(n) end Ready")
    #expect(s.detailReady && s.starters.count == 2 && s.skills.first?.name == "Resurrection")
    #expect(s.skills.first?.status == "Not enough SP" && s.supplies.first?.amount == 10)
    #expect(s.supplyBag.first?.amount == 20 && s.activity == "Low SP — no SP potions")
}
@Test func companionDetailsRejectPartialAndDuplicateFrames() {
    for bad in ["starter 0 1601 1", "supply 505 1001", "skill 54 11 4 20 30 0"] {
        var s = CompanionState(); let n = s.begin("inspect 1")
        for f in ["begin 1 1", "row 1 8 26 29 0 0 80 100 20 30 95000000 2 19 AI-Priest-1", "gearbegin 1 0 0 0", "detailbegin 1 2 1 1 0 6 1", "starter 0 1601 1", bad, "end Ready"] { s.receive("[RCO1] \(n) \(f)") }
        #expect(!s.ready && !s.detailReady && !s.pending)
    }
}

@Test func expandedPriestSkillTable() {
    var state = CompanionState()
    let token = state.begin("inspect 1")
    let frames = ["begin 1 1", "row 1 8 26 29 0 0 80 100 20 30 95000000 2 19 AI-Priest-1",
                  "gearbegin 1 0 0 0", "detailbegin 1 0 6 0 0 0 1",
                  "skill 28 3 10 1 20 0", "skill 34 2 10 5 20 0", "skill 29 2 10 5 20 0",
                  "skill 54 1 4 20 30 0", "skill 33 2 10 10 26 0", "skill 74 1 5 15 40 0", "end Ready"]
    for frame in frames { state.receive("[RCO1] \(token) \(frame)") }
    #expect(state.detailReady && state.skills.count == 6)
    #expect(state.skills.last?.name == "Magnificat")
    #expect(state.skills.last?.policyKey == "magnificat")
}

@Test func storedSwordsAndStarterSlotsHaveDistinctRows() {
    var state = CompanionState()
    state.equipment = [
        CompanionEquipment(id: 1, itemID: 1157, equipped: false, returning: false),
        CompanionEquipment(id: 2, itemID: 1154, equipped: true, returning: false),
    ]
    state.starters = [
        CompanionStarter(id: 0, itemID: 1201, equipped: false),
        CompanionStarter(id: 1, itemID: 2301, equipped: false),
    ]
    #expect(state.gearRows.map(\.id) == ["gear:1", "gear:2", "starter:0", "starter:1"])
    #expect(state.gearRows.map(\.itemID) == [1157, 1154, 1201, 2301])
}

@Test func autoPotionHintTracksServerInspections() {
    var state = CompanionState()
    for threshold in [65, 35, 50, 47, 0] {
        let token = state.begin("inspect 1")
        let rule = threshold == 0 ? "" : "Auto potion: HP <\(threshold)%, SP <30%."
        for frame in ["begin 1 1", "row 1 8 26 29 0 0 80 100 20 30 95000000 2 19 AI-Priest-1",
                      "gearbegin 1 0 0 0", "detailbegin 1 0 1 0 0 6 1", "skill 28 3 10 1 20 0", "end Ready. \(rule)"] {
            state.receive("[RCO1] \(token) \(frame)")
        }
        #expect(state.detailReady && state.message == "Ready.")
        #expect(state.potionRule == (threshold == 0 ? nil : rule))
    }
}
