import Testing
import RagnarokPackets
@testable import RagnarokGame

@Test func cashShopCatalogueAndPurchaseGuards() {
    var state = CashShopState()
    var list = PACKET_ZC_ACK_SCHEDULER_CASHITEM()
    list.tabNum = 6; list.count = 1; list.packetLength = 16
    var row = PACKET_ZC_ACK_SCHEDULER_CASHITEM_sub()
    row.itemId = 505; row.price = 5; list.items = [row]
    state.receive(list)
    state.receive(list)
    #expect(state.products.count == 1)
    let item = state.products[0]
    #expect(state.purchase(item, quantity: 1, useKafra: false) == nil)
    state.ready = true; state.cash = 5; state.kafra = 5
    #expect(state.purchase(item, quantity: 2, useKafra: false) == nil)
    let packet = state.purchase(item, quantity: 2, useKafra: true)
    #expect(packet?.packetLength == 20)
    #expect(packet?.items.first?.itemId == 505)
    #expect(packet?.items.first?.amount == 2)
    #expect(packet?.items.first?.tab == 6)
    #expect(packet?.kafraPoints == 5)
    #expect(state.purchase(item, quantity: 0, useKafra: true) == nil)
    #expect(state.purchase(item, quantity: 1000, useKafra: true) == nil)
    state.pending = true
    #expect(state.purchase(item, quantity: 1, useKafra: false) == nil)
    var result = PACKET_ZC_SE_PC_BUY_CASHITEM_RESULT()
    result.result = 4; result.cashPoints = 5; result.kafraPoints = 5
    state.receive(result)
    #expect(!state.pending && state.cash == 5)
    #expect(state.message == "Inventory is too heavy.")
    list.count = 3
    state.receive(list)
    #expect(state.products.count == 1)
}

@Test func cashShopCartSequentialAcknowledgementsAndFreePoints() {
    var state = CashShopState()
    let first = CashShopProduct(itemID: 505, price: 5, tab: 6)
    let second = CashShopProduct(itemID: 1201, price: 20, tab: 4)
    state.products = [first, second]; state.ready = true; state.cash = 100; state.kafra = 7
    state.addToCart(first); state.addToCart(first); state.addToCart(second)
    #expect(state.cartTotal == 30)
    #expect(!state.canPurchaseCart(freePoints: 8))
    let start = state.beginCartPurchase(freePoints: 7)
    #expect(start?.items.first?.amount == 1)
    #expect(start?.kafraPoints == 5)
    #expect(state.pending)
    #expect(state.beginCartPurchase(freePoints: 0) == nil)
    var ack = PACKET_ZC_SE_PC_BUY_CASHITEM_RESULT()
    ack.itemId = 505; ack.cashPoints = 100; ack.kafraPoints = 2
    let next = state.receivePurchaseResult(ack)
    #expect(next?.items.first?.itemId == 505 && next?.kafraPoints == 2)
    #expect(state.cartTotal == 25 && state.pending)
    ack.cashPoints = 97; ack.kafraPoints = 0
    let last = state.receivePurchaseResult(ack)
    #expect(last?.items.first?.itemId == 1201 && last?.kafraPoints == 0)
    ack.itemId = 1201; ack.cashPoints = 77
    #expect(state.receivePurchaseResult(ack) == nil)
    #expect(!state.pending && state.cart.isEmpty && state.cash == 77)
}

@Test func cashShopCartLimitsFailureAndTimeoutDoNotRetry() {
    var state = CashShopState()
    state.ready = true; state.cash = 1000
    state.products = (1...9).map { CashShopProduct(itemID: UInt32($0), price: 1, tab: 6) }
    for item in state.products { state.addToCart(item) }
    #expect(state.cart.count == 8)
    state.setQuantity(1000, for: state.cart[0].id)
    #expect(state.cart[0].quantity == 99)
    #expect(state.beginCartPurchase(freePoints: 0) != nil)
    var result = PACKET_ZC_SE_PC_BUY_CASHITEM_RESULT()
    result.itemId = 999
    #expect(state.receivePurchaseResult(result) == nil && state.pending)
    state.purchaseTimeout()
    result.itemId = 1
    #expect(state.receivePurchaseResult(result) == nil && state.pending)
    #expect(state.beginCartPurchase(freePoints: 0) == nil)

    var failure = CashShopState()
    failure.ready = true; failure.cash = 10; failure.products = [state.products[0]]
    failure.addToCart(state.products[0]); failure.addToCart(state.products[0])
    #expect(failure.beginCartPurchase(freePoints: 0) != nil)
    result.itemId = 1; result.cashPoints = 9
    #expect(failure.receivePurchaseResult(result) != nil)
    result.result = 4
    #expect(failure.receivePurchaseResult(result) == nil && !failure.pending)
    #expect(failure.cart[0].quantity == 1)
    #expect(failure.message?.contains("Check inventory") == true)
}

@Test func cashShopCartRejectsStalePriceAndDuplicateIdentity() {
    var state = CashShopState()
    state.ready = true; state.cash = 100
    let item = CashShopProduct(itemID: 505, price: 5, tab: 6)
    let otherTab = CashShopProduct(itemID: 505, price: 3, tab: 0)
    state.products = [item, otherTab]
    state.addToCart(item); state.addToCart(otherTab)
    #expect(state.cart.count == 1 && state.cart[0].quantity == 1)
    state.products[0].price = 6
    #expect(!state.canPurchaseCart(freePoints: 0))
    #expect(state.beginCartPurchase(freePoints: 0) == nil)
    state.setQuantity(0, for: item.id)
    #expect(state.cart.isEmpty)
    #expect(!state.canPurchaseCart(freePoints: 0))
}
