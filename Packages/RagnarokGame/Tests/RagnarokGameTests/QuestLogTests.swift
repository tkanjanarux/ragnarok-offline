import Testing
import RagnarokPackets
@testable import RagnarokGame

private func little(_ value: UInt32, _ count: Int) -> [UInt8] {
    (0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
}

@Test func questLifecycleAndMalformedPacket() {
    let questID: UInt32 = 11118, huntID: UInt32 = 11118000
    var entry = little(questID, 4) + [1] + little(0, 4) + little(0, 4) + little(1, 2)
    entry += little(huntID, 4) + little(0, 4) + little(1014, 4)
    entry += little(0, 2) + little(0, 2) + little(3, 2) + little(30, 2)
    entry += Array("Spore".utf8) + [UInt8](repeating: 0, count: 19)
    let list = [UInt8(0xf8), 9] + little(UInt32(entry.count + 8), 2) + little(1, 4) + entry
    var state = QuestLogDecoder.applying(.init(type: 0x9f8, bytes: list), to: [:])
    #expect(state[questID]?.objectives.first?.current == 3)
    #expect(state[questID]?.objectives.first?.required == 30)
    #expect(state[questID]?.objectives.first?.name == "Spore")
    let update = [UInt8(0xfa), 9, 18, 0, 1, 0] + little(questID, 4) + little(huntID, 4) + little(30, 2) + little(4, 2)
    state = QuestLogDecoder.applying(.init(type: 0x9fa, bytes: update), to: state)
    #expect(state[questID]?.objectives.first?.current == 4)
    state = QuestLogDecoder.applying(.init(type: 0x9f8, bytes: Array(list.dropLast())), to: state)
    #expect(state[questID]?.objectives.first?.current == 4)
    state = QuestLogDecoder.applying(.init(type: 0x2b4, bytes: [0xb4, 2] + little(questID, 4)), to: state)
    #expect(state.isEmpty)
}
