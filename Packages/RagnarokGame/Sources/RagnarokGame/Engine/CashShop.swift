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
    private var purchaseQueue: [CashShopCartLine] = []
    private var remainingFreePoints: UInt32 = 0
    private var cashBeforeRequest: UInt32 = 0
    private var kafraBeforeRequest: UInt32 = 0
    private var completedUnits = 0
    private(set) var checkingBalance = false
    static let balanceCheckTab: UInt32 = 0   // Normal shop opens request tab 6.

    mutating func purchaseTimeout() -> Bool {
        guard pending, !checkingBalance else { return false }
        checkingBalance = true
        message = "Checking the server balance. If it does not refresh, reconnect before buying again."
        return true
    }

    mutating func receiveBalance(cashPoints: UInt32, kafraPoints: UInt32, tab: UInt32) {
        if checkingBalance && tab == Self.balanceCheckTab {
            // The server processes the balance request after the outstanding buy on the same TCP stream.
            if let unresolved = purchaseQueue.first {
                if cashBeforeRequest == cashPoints && kafraBeforeRequest == kafraPoints {
                    message = "Order stopped. Balance unchanged. Review the cart before buying again."
                } else {
                    cart.removeAll { $0.product == unresolved.product }
                    message = "Balance updated. Check inventory before ordering this item again."
                }
            }
            purchaseQueue.removeAll()
            pending = false
            checkingBalance = false
        }
        cash = cashPoints
        kafra = kafraPoints
        ready = true
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

    // The six standard potions (501…506) grant a stack in one server reply.
    // For other catalogue entries the wire format does not specify GUID or stack rules.
    mutating func beginCartPurchase(freePoints: UInt32) -> PACKET_CZ_SE_PC_BUY_CASHITEM_LIST? {
        guard canPurchaseCart(freePoints: freePoints) else { return nil }
        purchaseQueue = cart.flatMap { line -> [CashShopCartLine] in
            if (501...506).contains(line.product.itemID) { return [line] }
            return Array(repeating: CashShopCartLine(product: line.product, quantity: 1), count: line.quantity)
        }
        remainingFreePoints = freePoints
        completedUnits = 0
        pending = true
        message = "Waiting for the server…"
        return nextPurchasePacket()
    }

    private mutating func nextPurchasePacket() -> PACKET_CZ_SE_PC_BUY_CASHITEM_LIST? {
        guard let line = purchaseQueue.first else { return nil }
        cashBeforeRequest = cash
        kafraBeforeRequest = kafra
        let product = line.product
        let free = min(remainingFreePoints, product.price * UInt32(line.quantity))
        var item = PACKET_CZ_SE_PC_BUY_CASHITEM_LIST_sub()
        item.itemId = product.itemID; item.amount = UInt32(line.quantity); item.tab = product.tab
        var packet = PACKET_CZ_SE_PC_BUY_CASHITEM_LIST()
        packet.packetType = HEADER_CZ_SE_PC_BUY_CASHITEM_LIST
        packet.packetLength = 20; packet.count = 1; packet.kafraPoints = free; packet.items = [item]
        return packet
    }

    mutating func receivePurchaseResult(_ packet: PACKET_ZC_SE_PC_BUY_CASHITEM_RESULT) -> PACKET_CZ_SE_PC_BUY_CASHITEM_LIST? {
        guard pending, let expected = purchaseQueue.first else {
            return nil
        }
        guard packet.result != 0 || packet.itemId == expected.product.itemID else { return nil }
        cash = packet.cashPoints; kafra = packet.kafraPoints
        if packet.result != 0 {
            let partial = completedUnits > 0
            purchaseQueue.removeAll()
            receive(packet)
            if checkingBalance { pending = true }
            if partial { message = "Purchase stopped after \(completedUnits) item(s). Check inventory. " + (message ?? "") }
            return nil
        }
        remainingFreePoints -= min(remainingFreePoints, expected.product.price * UInt32(expected.quantity))
        completedUnits += expected.quantity
        purchaseQueue.removeFirst()
        if let index = cart.firstIndex(where: { $0.product == expected.product }) {
            cart[index].quantity -= expected.quantity
            if cart[index].quantity == 0 { cart.remove(at: index) }
        }
        if checkingBalance {
            message = purchaseQueue.isEmpty ? "Purchase complete. Items added to inventory." : "Last purchase confirmed. Review the remaining cart."
            purchaseQueue.removeAll()
            return nil
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
        case 6, 12: message = "Cannot buy right now. Wait for the map to load or finish your current interaction."
        case 7, 9, 10: message = "Item quantity limit reached."
        case 8: message = "Some items could not be bought. Check your inventory."
        default: message = "Purchase failed (server code \(packet.result))."
        }
    }

    static let tabs = ["New", "Hot", "Limited", "Rental", "Permanent", "Scrolls", "Consumables", "Other", "Sale"]
}
