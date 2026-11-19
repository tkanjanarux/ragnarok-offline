import Foundation
import Testing
import RagnarokPackets
@testable import RagnarokGame

@Test @MainActor func renewalQuestCategoriesAndTracker() {
    let ui = QuestUIState()
    let now = Date(timeIntervalSince1970: 100)
    let active = (1...5).map { QuestEntry(id: UInt32($0), state: 1, expires: 0, objectives: []) }
    let quests = active + [.init(id: 6, state: 0, expires: 0, objectives: []), .init(id: 7, state: 1, expires: 200, objectives: [])]
    #expect(ui.visibleQuests(quests, now: now).count == 5)
    #expect(ui.trackedQuests(quests, now: now).map(\.id) == [1, 2, 3, 4])
    ui.toggleTracking(2)
    #expect(ui.trackedQuests(quests, now: now).map(\.id) == [1, 3, 4, 5])
    ui.tab = .cooldown
    #expect(ui.visibleQuests(quests, now: now).map(\.id) == [7])
    ui.tab = .feature
    #expect(ui.visibleQuests(quests, now: now).isEmpty)
    ui.showTracker = false
    #expect(ui.trackedQuests(quests, now: now).isEmpty)
    ui.selectedQuestID = 1
    ui.reset()
    #expect(ui.selectedQuestID == nil && ui.hiddenQuestIDs.isEmpty && ui.tab == .active)
}

@Test func questToggleAckAndMalformedUpdate() {
    let quests: [UInt32: QuestEntry] = [42: .init(id: 42, state: 1, expires: 0, objectives: [])]
    let inactive = QuestLogDecoder.applying(.init(type: 0x2b7, bytes: [0xb7, 2, 42, 0, 0, 0, 0]), to: quests)
    #expect(inactive[42]?.state == 0)
    #expect(quests[42]?.state == 1)
    let malformed = QuestLogDecoder.applying(.init(type: 0x8fe, bytes: [0xfe, 8, 0, 0]), to: quests)
    #expect(malformed[42]?.state == 1)
}
