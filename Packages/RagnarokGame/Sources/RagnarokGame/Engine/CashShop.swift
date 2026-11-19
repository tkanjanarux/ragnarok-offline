import RagnarokPackets

struct CashShopProduct: Identifiable, Equatable {
    var itemID: UInt32
    var price: UInt32
    var tab: UInt16
    var id: String { "\(tab):\(itemID)" }
}

struct CashShopCartLine: Identifiable, Equatable {
    var product: CashShopProduct
    var quantity: Int
    var id: String { product.id }
}

struct CashShopState {
    var cart: [CashShopCartLine] = []
    private var purchaseQueue: [CashShopProduct] = []
    private var remainingFreePoints: UInt32 = 0
    private var completedUnits = 0
    private var purchaseTimedOut = false

    mutating func purchaseTimeout() {
        purchaseTimedOut = true
        message = "No purchase response. Reconnect and check inventory before buying again."
    }
    var cartTotal: UInt64 { cart.reduce(0) { $0 + UInt64($1.product.price) * UInt64($1.quantity) } }

    mutating func addToCart(_ product: CashShopProduct) {
        guard !pending, products.contains(product) else { return }
        if let index = cart.firstIndex(where: { $0.product.itemID == product.itemID }) {
            guard cart[index].product == product, cart[index].quantity < 99 else { return }
            cart[index].quantity += 1
        } else if cart.count < 8 {
            cart.append(CashShopCartLine(product: product, quantity: 1))
        }
    }

    mutating func setQuantity(_ quantity: Int, for id: String) {
        guard !pending, let index = cart.firstIndex(where: { $0.id == id }) else { return }
        if quantity <= 0 { cart.remove(at: index) }
        else { cart[index].quantity = min(quantity, 99) }
    }

    func canPurchaseCart(freePoints: UInt32) -> Bool {
        ready && !pending && !cart.isEmpty && cart.count <= 8 &&
        cart.allSatisfy { (1...99).contains($0.quantity) && products.contains($0.product) } &&
        cartTotal <= UInt64(UInt32.max) && UInt64(freePoints) <= cartTotal &&
        freePoints <= kafra && cartTotal - UInt64(freePoints) <= UInt64(cash)
    }

    // rAthena acknowledges each inventory grant, not the whole buy list. GUID and
    // unstackable products have different grant counts, not exposed in the catalogue.
    // Send one unit at a time, advancing only on an acknowledgement, never on timeout.
    mutating func beginCartPurchase(freePoints: UInt32) -> PACKET_CZ_SE_PC_BUY_CASHITEM_LIST? {
        guard canPurchaseCart(freePoints: freePoints) else { return nil }
        purchaseQueue = cart.flatMap { Array(repeating: $0.product, count: $0.quantity) }
        remainingFreePoints = freePoints
        completedUnits = 0
        pending = true
        message = "Waiting for the server…"
        return nextPurchasePacket()
    }

    private mutating func nextPurchasePacket() -> PACKET_CZ_SE_PC_BUY_CASHITEM_LIST? {
        guard let product = purchaseQueue.first else { return nil }
        let free = min(remainingFreePoints, product.price)
        var item = PACKET_CZ_SE_PC_BUY_CASHITEM_LIST_sub()
        item.itemId = product.itemID; item.amount = 1; item.tab = product.tab
        var packet = PACKET_CZ_SE_PC_BUY_CASHITEM_LIST()
        packet.packetType = HEADER_CZ_SE_PC_BUY_CASHITEM_LIST
        packet.packetLength = 20; packet.count = 1; packet.kafraPoints = free; packet.items = [item]
        return packet
    }

    mutating func receivePurchaseResult(_ packet: PACKET_ZC_SE_PC_BUY_CASHITEM_RESULT) -> PACKET_CZ_SE_PC_BUY_CASHITEM_LIST? {
        guard !purchaseTimedOut else { return nil }
        guard pending, let expected = purchaseQueue.first else {
            if purchaseQueue.isEmpty && pending { receive(packet) }
            return nil
        }
        guard packet.result != 0 || packet.itemId == expected.itemID else { return nil }
        cash = packet.cashPoints; kafra = packet.kafraPoints
        if packet.result != 0 {
            let partial = completedUnits > 0
            purchaseQueue.removeAll()
            receive(packet)
            if partial { message = "Purchase stopped after \(completedUnits) item(s). Check inventory. " + (message ?? "") }
            return nil
        }
        remainingFreePoints -= min(remainingFreePoints, expected.price)
        completedUnits += 1
        purchaseQueue.removeFirst()
        if let index = cart.firstIndex(where: { $0.product == expected }) {
            cart[index].quantity -= 1
            if cart[index].quantity == 0 { cart.remove(at: index) }
        }
        if purchaseQueue.isEmpty {
            pending = false
            message = "Purchase complete. Items added to inventory."
            return nil
        }
        return nextPurchasePacket()
    }

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
        guard ready, !pending, (1...99).contains(quantity), products.contains(product) else { return nil }
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
