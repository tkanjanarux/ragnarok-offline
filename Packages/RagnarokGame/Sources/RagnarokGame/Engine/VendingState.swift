import Foundation
import RagnarokPackets

struct VendingState {
    struct Board: Identifiable { let id: UInt32; let name: String }
    struct Purchase {
        let owner: UInt32, shop: UInt32, index: UInt16, itemID: UInt32, amount: UInt16
        let beforeZeny: Int, cost: Int
        var received = 0
    }
    var visible = false
    var boards: [UInt32: Board] = [:]
    var preparingSlots = 0
    var active = false
    var own: [PACKET_ZC_PC_PURCHASE_MYITEMLIST_sub] = []
    var browsing: UInt32?
    var shop: PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC?
    var draft: [UInt16: VendingRequest.Entry] = [:]
    var purchase: Purchase?
    var waiting: UUID?
    var message: String?
    mutating func receive(_ p: PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC) {
        guard browsing == p.AID, purchase == nil else { return }; shop = p; waiting = nil; message = nil
    }
    mutating func receivedItem(_ id: UInt32, count: UInt16, zeny: Int) {
        guard purchase?.itemID == id else { return }
        purchase?.received += Int(count); checkPurchase(zeny: zeny)
    }
    mutating func checkPurchase(zeny: Int) {
        guard let p = purchase, p.received == Int(p.amount), zeny == p.beforeZeny - p.cost else { return }
        purchase = nil; waiting = nil; shop = nil; browsing = nil; message = "Purchase completed."
    }
    mutating func vanished(_ id: UInt32) {
        boards.removeValue(forKey: id)
        if browsing == id, purchase == nil { shop = nil; browsing = nil; waiting = nil; message = "This shop is no longer nearby." }
    }
}

extension PlaySession {
    func browseVending(_ owner: UInt32) {
        guard enchant.pending == nil, !buyingStore.busy, vending.waiting == nil, !vending.active, !rodex.busy, !trade.active, trade.waiting == nil,
              vending.boards[owner] != nil, mapScene?.objects[owner] != nil else { return }
        vending.visible = true; vending.shop = nil; vending.browsing = owner
        waitForVending(); sendFoundationPacket(VendingRequest.browse(owner))
    }
    func buyVending(index: UInt16, amount: UInt16) {
        guard enchant.pending == nil, !buyingStore.busy, vending.waiting == nil, !rodex.busy, !trade.active, bank.pending == nil, let shop = vending.shop,
              let item = shop.items.first(where: { UInt16(bitPattern: $0.index) == index }), amount > 0, amount <= item.amount else { return }
        let cost = UInt64(amount) * UInt64(item.price)
        guard cost <= UInt64(max(0,playerStatus.zeny)), cost <= UInt64(Int.max) else { return }
        vending.purchase = .init(owner: shop.AID, shop: shop.venderId, index: index, itemID: item.itemId, amount: amount, beforeZeny: playerStatus.zeny, cost: Int(cost))
        waitForVending(); sendFoundationPacket(VendingRequest.buy(shop.AID, shop.venderId, index, amount))
    }
    func addVendingDraft(index: Int, amount: Int, price: UInt32) {
        guard vending.preparingSlots > 0, vending.waiting == nil, let item = cart.inventory.items[index],
              let wire = UInt16(exactly: index), amount > 0, amount <= item.amount, amount <= Int(Int16.max), price > 0,
              vending.draft.count < vending.preparingSlots || vending.draft[wire] != nil else { return }
        vending.draft[wire] = .init(index: wire, amount: UInt16(amount), price: price)
    }
    func openVending(name: String) {
        guard !rodex.busy, !trade.active, bank.pending == nil, cart.pending == nil, vending.waiting == nil,
              vending.preparingSlots > 0, !vending.draft.isEmpty, vending.draft.count <= vending.preparingSlots,
              !name.isEmpty, name.utf8.count < 80, !name.contains("\0") else { return }
        waitForVending(); sendFoundationPacket(VendingRequest.open(name, vending.draft.values.sorted { $0.index < $1.index }))
    }
    func closeVending() {
        guard vending.purchase == nil, vending.waiting == nil else { vending.visible = false; return }
        if vending.preparingSlots > 0 { sendFoundationPacket(VendingRequest.cancel) }
        vending.preparingSlots = 0; vending.draft = [:]; vending.shop = nil; vending.browsing = nil; vending.visible = false
    }
    func endVending() {
        guard vending.active else { return }
        sendFoundationPacket(VendingRequest.close)
        vending.active = false; vending.own = []; vending.message = "Shop close requested."
    }
    private func waitForVending() {
        let token = UUID(); vending.waiting = token; vending.message = "Waiting for the server…"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, self.vending.waiting == token else { return }
            self.vending.message = "No server result. Reconnect before trying again."
        }
    }
}
