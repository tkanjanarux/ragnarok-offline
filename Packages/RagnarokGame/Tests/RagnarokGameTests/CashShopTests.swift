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
