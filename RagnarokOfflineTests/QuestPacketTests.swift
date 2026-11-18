import Foundation
import XCTest
@testable import RagnarokPackets

final class QuestPacketTests: XCTestCase {
    func testFragmentedQuestListAndFollowingDelete() throws {
        let decoder = PacketDecoder()
        // Empty list followed by deletion of quest 11118; network chunks split headers.
        let bytes: [UInt8] = [0xf8, 0x09, 8, 0, 0, 0, 0, 0, 0xb4, 2, 0x6e, 0x2b, 0, 0]
        var packets: [QuestWirePacket] = []
        for byte in bytes {
            try decoder.decode(from: Data([byte])) {
                if let packet = $0 as? QuestWirePacket { packets.append(packet) }
            }
        }
        XCTAssertEqual(packets.map(\.type), [0x9f8, 0x2b4])
        XCTAssertEqual(packets.map { $0.bytes.count }, [8, 6])
    }

    func testFixedLengthAddDoesNotConsumeNextPacket() throws {
        var bytes = [UInt8](repeating: 0, count: 143)
        bytes[0] = 0xf9; bytes[1] = 9
        bytes += [0xb4, 2, 1, 0, 0, 0]
        var types: [Int16] = []
        try PacketDecoder().decode(from: Data(bytes)) {
            if let packet = $0 as? QuestWirePacket { types.append(packet.type) }
        }
        XCTAssertEqual(types, [0x9f9, 0x2b4])
    }
}
