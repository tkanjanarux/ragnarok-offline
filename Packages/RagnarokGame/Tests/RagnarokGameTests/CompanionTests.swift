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
    s.receive("[RCO1] \(t) gear 9 1157 34 0")
    s.receive("[RCO1] \(t) bag 4 2301 7654321")
    #expect(!s.equipmentReady && s.equipment.isEmpty)
    s.receive("[RCO1] \(t) end Waiting.")
    #expect(s.equipmentReady && s.equipmentProfile == 2 && s.transferPending && s.completedSequence == t)
    #expect(s.equipment[0].equipMask == 34)
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

@Test func detailsResumeAfterTransferTimeoutWithoutRepeatingTransfer() {
    var state = CompanionState()
    let transfer = state.begin("giveui 3 1:4294967314")
    #expect(state.detailRefreshAction(for: 3) == nil)
    state.timeout(transfer)
    #expect(state.detailRefreshAction(for: 3) == "list")
    let roster = state.begin("list")
    state.receive("[RCO1] \(roster) begin 0 1")
    state.receive("[RCO1] \(roster) end Ready.")
    #expect(state.detailRefreshAction(for: 3) == "inspect 3")
}

@Test func socketedEquipmentKeepsRefineAndRepeatedCardsInBothLists() {
    var state = CompanionState()
    let n = state.begin("equipment 1")
    for line in ["begin 1 1","row 1 7 52 44 0 0 900 900 100 100 0 0 0 Knight","gearbegin 1 1 1 0",
                 "gear 8 1101 2 0 7 4004 4004 0 0","bag 12 1101 4294967324 9 0 0 0 0","end Ready"] {
        state.receive("[RCO1] \(n) \(line)")
    }
    #expect(state.equipmentReady)
    #expect(state.gearRows.first?.details == CompanionItemDetails(refine: 7, cards: [4004,4004]))
    #expect(state.bag.first?.details.refine == 9)
}

@Test func nearbyHuntStateFollowsCompletedServerSnapshot() {
    var state = CompanionState()
    for hunt in [0, 1, 0] {
        let seq = state.begin("list")
        state.receive("[RCO1] \(seq) begin 0 1")
        state.receive("[RCO1] \(seq) hunt \(hunt)")
        state.receive("[RCO1] \(seq) end Ready.")
        #expect(state.ready && state.nearbyHunt == (hunt == 1))
    }
    let seq = state.begin()
    state.receive("[RCO1] \(seq) begin 0 1")
    state.receive("[RCO1] \(seq) end Ready.")
    #expect(state.ready && state.nearbyHunt == nil)
}

@Test func allSecondJobTablesAndSwitches() {
    let tables = [(7,[5,6,8,62,56,60,59]), (8,[28,34,29,54,33,74,66,73,75]), (9,[19,14,20,90,84,86])]
    let keys = [56:"pierce",60:"quicken",59:"spearboomerang",66:"impositio",73:"kyrie",75:"gloria",86:"waterball"]
    for (job,ids) in tables {
        var state = CompanionState()
        let token = state.begin("inspect 1")
        let start = ["begin 1 1", "row 1 \(job) 90 50 0 0 80 100 20 30 95000000 2 0 Tester", "gearbegin 1 0 0 0", "detailbegin 1 0 \(ids.count) 0 0 0 1"]
        let frames = start + ids.map { "skill \($0) 1 5 1 10 0" } + ["end Ready"]
        for frame in frames { state.receive("[RCO1] \(token) \(frame)") }
        #expect(state.detailReady && state.skills.count == ids.count)
        for skill in state.skills {
            if let key = keys[Int(skill.id)] {
                #expect(skill.policyKey == key && !skill.name.contains("#"))
            }
        }
    }
}

@Test func enableConditionalCompanionSkillsBeforeRepeatableAttacks() {
    let quicken = CompanionSkill(id: 60, level: 1, maximum: 10, unlock: 12, sp: 14, reason: 0)
    #expect(quicken.toggling(in: ["provoke", "bash"]) == ["provoke", "quicken", "bash"])
    #expect(quicken.toggling(in: ["quicken", "bash"]) == ["bash"])
}

@Test func fourActiveCompanionsAndOneInReserve() {
    var state = CompanionState()
    let seq = state.begin("list")
    state.receive("[RCO1] \(seq) begin 5 1")
    for (i, job) in [7,8,9,11,7].enumerated() {
        let active = i < 4
        state.receive("[RCO1] \(seq) row \(i+1) \(job) 81 36 0 0 100 100 20 30 \(active ? 95000000+i : 0) \(active ? 2 : 0) 0 AI-\(i+1) custom")
    }
    state.receive("[RCO1] \(seq) end Ready.")
    #expect(state.ready && state.profiles.count == 5)
    #expect(state.activeCount == 4 && state.activeCount == CompanionState.activeLimit)
    #expect(state.profiles.last?.active == false)
}
