import XCTest
@testable import RagnarokPackets

final class CashShopPacketTests: XCTestCase {
    func testCashShopRequestBytes() throws {
        let encoder = PacketEncoder()
        XCTAssertEqual(Array(try encoder.encode(CashShopRequest(.list))), [0xc9, 0x08])
        XCTAssertEqual(Array(try encoder.encode(CashShopRequest(.close))), [0x4a, 0x08])
        var open = PACKET_CZ_SE_CASHSHOP_OPEN2()
        open.packetType = HEADER_CZ_SE_CASHSHOP_OPEN2; open.tab = 6
        XCTAssertEqual(Array(try encoder.encode(open)), [0x6d, 0x0b, 6, 0, 0, 0])
        var item = PACKET_CZ_SE_PC_BUY_CASHITEM_LIST_sub()
        item.itemId = 505; item.amount = 2; item.tab = 6
        var buy = PACKET_CZ_SE_PC_BUY_CASHITEM_LIST()
        buy.packetType = HEADER_CZ_SE_PC_BUY_CASHITEM_LIST
        buy.packetLength = 20; buy.count = 1; buy.kafraPoints = 5; buy.items = [item]
        XCTAssertEqual(Array(try encoder.encode(buy)), [0x48, 8, 20, 0, 1, 0, 5, 0, 0, 0, 0xf9, 1, 0, 0, 2, 0, 0, 0, 6, 0])
    }
}
