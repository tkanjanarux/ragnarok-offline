import Foundation
import RagnarokModels
import RagnarokPackets

struct CartState {
    var inventory = Inventory()
    var available = false
    var count = 0
    var capacity = 0
    var weight = 0
    var maximumWeight = 0
    var visible = false
    var message: String?
    struct Transfer {
        var token = UUID()
        var toCart: Bool
        var index: Int
        var itemID: Int
        var amount: Int
        var receivedSource = false
        var receivedDestination = false
    }
    var pending: Transfer?

    mutating func receiveCount(_ packet: PACKET_ZC_NOTIFY_CARTITEM_COUNTINFO) {
        available = true
        count = Int(packet.curCount); capacity = Int(packet.maxCount)
        weight = Int(packet.curWeight); maximumWeight = Int(packet.maxWeight)
    }
    mutating func receiveAdded(_ packet: PACKET_ZC_ADD_ITEM_TO_CART) {
        guard packet.amount > 0 else { return }
        let index = Int(packet.index)
        var item = inventory.items[index] ?? InventoryItem()
        item.index = index; item.itemID = Int(packet.itemId)
        item.type = .init(rawValue: Int(packet.itemType)) ?? .etc
        item.amount += Int(packet.amount)
        item.isIdentified = packet.identified != 0; item.isDamaged = packet.damaged != 0
        item.refineLevel = Int(packet.refine); item.slots = packet.slot.card.map(Int.init)
        inventory.items[index] = item
        receiveTransferEvent(toCart: true, source: false, index: index, itemID: item.itemID, amount: Int(packet.amount))
    }
    mutating func receiveRemoved(_ packet: PACKET_ZC_DELETE_ITEM_FROM_CART) {
        let index = Int(packet.index), amount = Int(packet.amount)
        guard amount > 0, var item = inventory.items[index] else { return }
        item.amount -= amount
        if item.amount <= 0 { inventory.items.removeValue(forKey: index) }
        else { inventory.items[index] = item }
        receiveTransferEvent(toCart: false, source: true, index: index, itemID: item.itemID, amount: amount)
    }
    mutating func receiveTransferEvent(toCart: Bool, source: Bool, index: Int, itemID: Int, amount: Int) {
        guard var transfer = pending, transfer.toCart == toCart,
              transfer.amount == amount, source ? transfer.index == index : transfer.itemID == itemID else { return }
        if source { transfer.receivedSource = true } else { transfer.receivedDestination = true }
        if transfer.receivedSource && transfer.receivedDestination {
            pending = nil; message = "Transfer complete."
        } else { pending = transfer }
    }
}

extension PlaySession {
    func moveCartItem(index: Int, amount: Int, toCart: Bool) {
        guard enchant.pending == nil, !buyingStore.busy, !vending.active, vending.purchase == nil, !rodex.busy, !trade.active, trade.waiting == nil else { return }
        let source = toCart ? inventory : cart.inventory
        guard cart.available, cart.pending == nil, itemSelection.pending == nil,
              let item = source.items[index], !item.isEquipped, amount > 0, amount <= item.amount,
              let index16 = Int16(exactly: index), let amount32 = Int32(exactly: amount) else { return }
        cart.pending = .init(toCart: toCart, index: index, itemID: item.itemID, amount: amount)
        cart.message = "Waiting for the server…"
        if toCart {
            var packet = PACKET_CZ_MOVE_ITEM_FROM_BODY_TO_CART()
            packet.packetType = HEADER_CZ_MOVE_ITEM_FROM_BODY_TO_CART
            packet.index = index16; packet.count = amount32
            sendFoundationPacket(packet)
        } else {
            var packet = PACKET_CZ_MOVE_ITEM_FROM_CART_TO_BODY()
            packet.packetType = HEADER_CZ_MOVE_ITEM_FROM_CART_TO_BODY
            packet.index = UInt16(bitPattern: index16); packet.amount = amount32
            sendFoundationPacket(packet)
        }
        let token = cart.pending?.token
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, let token, self.cart.pending?.token == token else { return }
            self.cart.message = "No complete server reply. Reconnect before trying again."
        }
    }
}
