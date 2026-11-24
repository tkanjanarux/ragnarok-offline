import Foundation
import RagnarokModels
import RagnarokPackets

struct BuyingStoreState {
    struct Sale { let index: Int, itemID: Int, amount: Int, price: UInt32 }
    var visible = false
    var boards: [UInt32: String] = [:]
    var slots = 0
    var active = false
    var own: PACKET_ZC_MYITEMLIST_BUYING_STORE?
    var draft: [UInt32: PACKET_CZ_REQ_OPEN_BUYING_STORE_sub] = [:]
    var browsing: UInt32?
    var shop: PACKET_ZC_ACK_ITEMLIST_BUYING_STORE?
    var sale: Sale?
    var waiting: UUID?
    var message: String?
    var busy: Bool { active || waiting != nil || slots > 0 }
    mutating func receive(_ packet: BuyingStoreSold, inventory: inout Inventory) {
        guard let sale, sale.index == Int(packet.index), sale.amount == Int(packet.amount), sale.price == packet.price,
              inventory.items[sale.index]?.itemID == sale.itemID, (inventory.items[sale.index]?.amount ?? 0) >= sale.amount else { return }
        // 081c replaces the server's suppressed inventory deletion; never also subtract on a request.
        inventory.items[sale.index]?.amount -= sale.amount
        if inventory.items[sale.index]?.amount == 0 { inventory.items.removeValue(forKey: sale.index) }
        self.sale = nil; waiting = nil; shop = nil; message = "Items sold."
        // Zeny is supplied separately by the server's status packet.
    }
    mutating func vanished(_ id: UInt32) {
        boards.removeValue(forKey: id)
        if browsing == id, sale == nil { shop = nil; browsing = nil; waiting = nil }
    }
}
extension PlaySession {
    func browseBuyingStore(_ id: UInt32) {
        guard enchant.pending == nil, !buyingStore.busy, !vending.active, vending.purchase == nil, !rodex.busy, !trade.active,
              buyingStore.boards[id] != nil, mapScene?.objects[id] != nil else { return }
        buyingStore.visible = true; buyingStore.browsing = id; buyingStore.shop = nil
        waitForBuyingStore(); sendFoundationPacket(BuyingStoreRequest.browse(id))
    }
    func addBuyingDraft(itemID: Int, amount: Int, price: UInt32) {
        guard buyingStore.slots > 0, buyingStore.waiting == nil, let id = UInt32(exactly: itemID), amount > 0, amount <= Int(Int16.max), price > 0,
              inventory.items.values.contains(where: { $0.itemID == itemID }),
              buyingStore.draft.count < buyingStore.slots || buyingStore.draft[id] != nil else { return }
        var row = PACKET_CZ_REQ_OPEN_BUYING_STORE_sub(); row.itemId = id; row.amount = UInt16(amount); row.price = price
        buyingStore.draft[id] = row
    }
    func createBuyingStore(name: String, budget: UInt32) {
        guard buyingStore.slots > 0, buyingStore.waiting == nil, !buyingStore.draft.isEmpty,
              !name.isEmpty, name.utf8.count < 80, !name.contains("\0"), budget > 0, UInt64(budget) <= UInt64(max(0,playerStatus.zeny)),
              !rodex.busy, !trade.active, !vending.active else { return }
        waitForBuyingStore(); sendFoundationPacket(BuyingStoreRequest.open(name,budget,buyingStore.draft.values.sorted { $0.itemId < $1.itemId }))
    }
    func sellToBuyingStore(index: Int, amount: Int) {
        guard buyingStore.waiting == nil, let shop = buyingStore.shop, let item = inventory.items[index], !item.isEquipped,
              let row = shop.items.first(where: { Int($0.itemId) == item.itemID }), amount > 0, amount <= item.amount, amount <= Int(row.amount),
              let wire = UInt16(exactly: index), UInt64(amount) * UInt64(row.price) <= UInt64(shop.zenyLimit), !rodex.busy, !trade.active else { return }
        buyingStore.sale = .init(index: index,itemID: item.itemID,amount: amount,price: row.price)
        waitForBuyingStore(); sendFoundationPacket(BuyingStoreRequest.sell(owner: shop.AID,store: shop.storeId,index: wire,item: row.itemId,amount: UInt16(amount)))
    }
    func closeBuyingWindow() {
        guard buyingStore.waiting == nil else { buyingStore.visible = false; return }
        if buyingStore.slots > 0 { sendFoundationPacket(BuyingStoreRequest.cancel); buyingStore.slots = 0; buyingStore.draft = [:] }
        buyingStore.visible = false; buyingStore.shop = nil; buyingStore.browsing = nil
    }
    func endBuyingStore() {
        guard buyingStore.active else { return }; sendFoundationPacket(BuyingStoreRequest.close)
        buyingStore.active = false; buyingStore.own = nil; buyingStore.message = "Shop close requested."
    }
    private func waitForBuyingStore() {
        let token = UUID(); buyingStore.waiting = token; buyingStore.message = "Waiting for the server…"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, self.buyingStore.waiting == token else { return }
            self.buyingStore.message = "No server result. Reconnect before trying again."
        }
    }
}
