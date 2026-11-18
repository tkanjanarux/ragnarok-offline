import RagnarokPackets

struct CashShopProduct: Identifiable, Equatable {
    var itemID: UInt32
    var price: UInt32
    var tab: UInt16
    var id: String { "\(tab):\(itemID)" }
}

struct CashShopState {
    // The server sends its catalogue once per map connection, sometimes before opening.
    var products: [CashShopProduct] = []
    var cash: UInt32 = 0
    var kafra: UInt32 = 0
    var ready = false
    var pending = false
    var message: String?

    mutating func receive(_ packet: PACKET_ZC_ACK_SCHEDULER_CASHITEM) {
        guard packet.tabNum >= 0, packet.tabNum <= 8,
              packet.count >= 0, Int(packet.count) == packet.items.count,
              Int(packet.packetLength) == 8 + packet.items.count * 8 else { return }
        // Large categories can arrive in several chunks. Merge rather than replace.
        for item in packet.items {
            let product = CashShopProduct(itemID: item.itemId, price: item.price, tab: UInt16(packet.tabNum))
            if let i = products.firstIndex(where: { $0.id == product.id }) {
                products[i] = product
            } else { products.append(product) }
        }
    }

    func purchase(_ product: CashShopProduct, quantity: Int, useKafra: Bool) -> PACKET_CZ_SE_PC_BUY_CASHITEM_LIST? {
        guard ready, !pending, (1...999).contains(quantity), products.contains(product) else { return nil }
        let total = UInt64(product.price) * UInt64(quantity)
        let kafraUsed = useKafra ? min(total, UInt64(kafra)) : 0
        guard total <= UInt64(UInt32.max), total - kafraUsed <= UInt64(cash) else { return nil }
        var item = PACKET_CZ_SE_PC_BUY_CASHITEM_LIST_sub()
        item.itemId = product.itemID
        item.amount = UInt32(quantity)
        item.tab = product.tab
        var packet = PACKET_CZ_SE_PC_BUY_CASHITEM_LIST()
        packet.packetType = HEADER_CZ_SE_PC_BUY_CASHITEM_LIST
        packet.packetLength = 20
        packet.count = 1
        packet.kafraPoints = UInt32(kafraUsed)
        packet.items = [item]
        return packet
    }

    mutating func receive(_ packet: PACKET_ZC_SE_PC_BUY_CASHITEM_RESULT) {
        cash = packet.cashPoints
        kafra = packet.kafraPoints
        pending = false
        switch packet.result {
        case 0: message = "Purchase complete. Items added to inventory."
        case 2: message = "Not enough Cash / Kafra Points."
        case 3: message = "This item is no longer available. Reconnect to refresh the shop."
        case 4: message = "Inventory is too heavy."
        case 5: message = "Not enough inventory slots."
        case 6, 12: message = "Cannot buy right now. Finish trading or talking to an NPC first."
        case 7, 9, 10: message = "Item quantity limit reached."
        case 8: message = "Some items could not be bought. Check your inventory."
        default: message = "Purchase failed (server code \(packet.result))."
        }
    }

    static let tabs = ["New", "Hot", "Limited", "Rental", "Permanent", "Scrolls", "Consumables", "Other", "Sale"]
}
