import XCTest
@testable import RagnarokPackets

final class QuestActiveRequestTests: XCTestCase {
    func testActiveQuestRequestIsSevenBytes() throws {
        let encoder = PacketEncoder()
        XCTAssertEqual(Array(try encoder.encode(QuestActiveRequest(questID: 0x12345678, active: true))), [0xb6, 2, 0x78, 0x56, 0x34, 0x12, 1])
        XCTAssertEqual(Array(try encoder.encode(QuestActiveRequest(questID: 42, active: false))), [0xb6, 2, 42, 0, 0, 0, 0])
    }
}
