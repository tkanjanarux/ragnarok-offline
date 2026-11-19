import XCTest
@testable import RagnarokPackets

final class PartyOptionsTests: XCTestCase {
    func testNormalPartyOptionRequest() throws {
        let encoder = PacketEncoder()
        XCTAssertEqual(Array(try encoder.encode(PartyOptionsRequest(exp: true, pickup: false, distribution: true))), [0xd7, 7, 1, 0, 0, 0, 0, 1])
        XCTAssertEqual(Array(try encoder.encode(PartyOptionsRequest(exp: false, pickup: false, distribution: false))), [0xd7, 7, 0, 0, 0, 0, 0, 0])
    }
}
