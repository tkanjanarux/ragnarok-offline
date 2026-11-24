import Foundation
import RagnarokModels
import RagnarokPackets

struct TradeState {
    struct Offer: Identifiable { let id = UUID(); var item: InventoryItem }
    struct Pending { let token = UUID(); let index: Int; let amount: Int; let item: InventoryItem }
    var visible = false
    var active = false
    var invitation = false
    var partnerID: UInt32?
    var partnerName = ""
    var mine: [Int: InventoryItem] = [:]
    var theirs: [Offer] = []
    var offeredZeny = 0 // request, not an acknowledged balance change
    var receivedZeny = 0
    var locked = false
    var otherLocked = false
    var pending: Pending?
    var waiting: UUID?
    var message: String?

    mutating func receiveAdd(_ packet: PACKET_ZC_ACK_ADD_EXCHANGE_ITEM, inventory: inout Inventory) {
        guard active, let request = pending, request.index == Int(packet.index) else { return }
        pending = nil; waiting = nil
        guard packet.result == 0 else { message = "The item was rejected (\(packet.result))."; return }
        guard inventory.items[request.index]?.itemID == request.item.itemID,
              (inventory.items[request.index]?.amount ?? 0) >= request.amount else {
            message = "Inventory changed. Cancel this trade and reconnect."; return
        }
        var item = request.item; item.amount = (mine[request.index]?.amount ?? 0) + request.amount
        mine[request.index] = item
        // The server reserves items with ACK only, suppresses commit deletion, and
        // sends pickup packets to restore them on cancellation. Apply exactly once.
        inventory.items[request.index]?.amount -= request.amount
        if inventory.items[request.index]?.amount == 0 { inventory.items.removeValue(forKey: request.index) }
        message = nil
    }
    mutating func receiveOther(_ p: PACKET_ZC_ADD_EXCHANGE_ITEM) {
        guard active, !otherLocked, p.amount >= 0 else { return }
        if p.itemId == 0 { receivedZeny = Int(p.amount); return }
        var item = InventoryItem(); item.itemID = Int(p.itemId); item.amount = Int(p.amount)
        item.isIdentified = p.identified != 0; item.refineLevel = Int(p.refine); item.isDamaged = p.damaged != 0
        item.slots = p.slot.card.map(Int.init)
        item.enchantGrade = Int(p.grade); item.hasRandomOptions = p.option_data.contains { $0.index != 0 }
        item.randomOptions = p.option_data.filter { $0.index != 0 }.map(InventoryItem.Option.init)
        theirs.append(.init(item: item))
    }
    mutating func finish(_ message: String) {
        active = false; invitation = false; pending = nil; waiting = nil
        mine = [:]; theirs = []; offeredZeny = 0; receivedZeny = 0
        locked = false; otherLocked = false; self.message = message
    }
}

extension PlaySession {
    func inviteSelectedPlayerToTrade() {
        guard enchant.pending == nil, !buyingStore.busy, !vending.active, vending.purchase == nil, !rodex.busy, !trade.active, trade.waiting == nil, let target = mapScene?.selectedTarget,
              target.type == .pc, target.objectID != partyAccountID,
              bank.pending == nil, cart.pending == nil, itemSelection.pending == nil, refine.pending == nil else { return }
        trade = TradeState(); trade.visible = true; trade.partnerID = target.objectID; trade.partnerName = target.name
        sendFoundationPacket(TradeRequest.invite(target.objectID)); awaitTrade()
    }
    func replyToTrade(accept: Bool) {
        guard trade.invitation else { return }
        if accept && (rodex.busy || buyingStore.busy || vending.active || vending.purchase != nil || bank.pending != nil) { return }
        trade.invitation = false
        sendFoundationPacket(TradeRequest.reply(accept)); awaitTrade()
    }
    func addTradeItem(index: Int, amount: Int) {
        guard trade.active, !trade.locked, trade.waiting == nil, trade.pending == nil,
              let item = inventory.items[index], !item.isEquipped,
              amount > 0, amount <= item.amount, amount <= Int(Int16.max),
              mineTradeSlotAvailable(index), let wireIndex = UInt16(exactly: index) else { return }
        trade.pending = .init(index: index, amount: amount, item: item)
        var p = PACKET_CZ_ADD_EXCHANGE_ITEM(); p.packetType = HEADER_CZ_ADD_EXCHANGE_ITEM
        p.index = wireIndex; p.amount = Int32(amount); sendFoundationPacket(p); awaitTrade()
    }
    private func mineTradeSlotAvailable(_ index: Int) -> Bool { trade.mine[index] != nil || trade.mine.count < 10 }
    func lockTrade(zeny: Int32) {
        guard trade.active, !trade.locked, trade.waiting == nil, trade.pending == nil,
              zeny >= 0, Int(zeny) <= playerStatus.zeny else { return }
        trade.offeredZeny = Int(zeny)
        var p = PACKET_CZ_ADD_EXCHANGE_ITEM(); p.packetType = HEADER_CZ_ADD_EXCHANGE_ITEM
        p.index = 0; p.amount = zeny; sendFoundationPacket(p)
        // Zeny has no individual ACK. The following server lock acknowledges the offer.
        sendFoundationPacket(TradeRequest.lock); awaitTrade()
    }
    func commitTrade() {
        guard trade.active, trade.locked, trade.otherLocked, trade.waiting == nil else { return }
        sendFoundationPacket(TradeRequest.commit); awaitTrade()
    }
    func cancelTrade() {
        if trade.active || trade.waiting != nil || trade.invitation {
            sendFoundationPacket(trade.invitation ? TradeRequest.reply(false) : TradeRequest.cancel)
            trade.invitation = false; awaitTrade()
        } else { trade.visible = false }
    }
    private func awaitTrade() {
        let token = UUID(); trade.waiting = token; trade.message = "Waiting for the server…"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, self.trade.waiting == token else { return }
            self.trade.message = "No server response. Cancel or reconnect before trying again."
        }
    }
}
