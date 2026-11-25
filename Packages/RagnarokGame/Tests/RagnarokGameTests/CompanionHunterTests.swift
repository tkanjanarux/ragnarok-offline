import Testing
@testable import RagnarokGame

@Test func hunterFramesAndArcherToggles() {
    let arrows = Array(1750...1757)
    let potions = [501,502,503,504,505,569,11621,11622,11623,11624]
    for job in [3,11] {
        var state = CompanionState()
        let seq = state.begin("inspect 4")
        let ids = job == 11 ? [43,44,45,46,126] : [43,44,45,46]
        let items = arrows + potions
        var frames = ["begin 1 1", "row 4 \(job) 78 32 0 0 80 100 20 30 95000005 2 0 AI-Hunter-4 conserve",
                      "gearbegin 4 0 0 0", "detailbegin 4 2 \(ids.count) 18 8 6 1", "starter 0 1701 1", "starter 1 2301 1"]
        frames += ids.map { "skill \($0) 10 10 2 0 0" }
        frames += items.map { "supply \($0) 1000" }
        frames += arrows.enumerated().map { "supplybag \($0.offset+1) \($0.element) 3" }
        for f in frames + ["end Ready"] { state.receive("[RCO1] \(seq) \(f)") }
        #expect(state.detailReady)
        #expect(state.profiles.first?.jobName == (job == 3 ? "Archer" : "Hunter"))
        #expect(state.supplies.count == 18 && state.supplyBag.count == 8)
        #expect(state.skills.compactMap(\.policyKey) == ["concentration","double"])
        #expect(state.skills.first { $0.id == 45 }?.toggling(in: ["double"]) == ["concentration","double"])
    }
}
