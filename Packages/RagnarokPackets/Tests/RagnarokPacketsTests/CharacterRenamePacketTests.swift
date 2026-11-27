import XCTest
import BinaryIO
@testable import RagnarokPackets

final class CharacterRenamePacketTests: XCTestCase {
    func testModernRenameRequestLayout() throws {
        let data = try PacketEncoder().encode(CharacterRenameRequest(characterID: 0x12345678, name: "NewName"))
        XCTAssertEqual(data.count, 30)
        XCTAssertEqual(Array(data.prefix(6)), [0xfc, 0x08, 0x78, 0x56, 0x34, 0x12])
        XCTAssertEqual(Array(data[6..<13]), Array("NewName".utf8))
        XCTAssertTrue(data[13...].allSatisfy { $0 == 0 })
    }
}
