import Foundation
import RagnarokPackets

extension PlaySession {
    func receiveItemSelection(_ packet: ItemSelectionList) {
        if packet.type == 0x177 {
            itemSelection.show(.identify, values: packet.indices.map(Int.init))
        } else if itemSelection.requestedCard != nil {
            itemSelection.show(.card, values: packet.indices.map(Int.init))
        }
    }

    func requestCardComposition(index: Int) {
        guard itemSelection.pending == nil, itemSelection.requestedCard == nil,
              let item = inventory.items[index], item.type == .card, item.amount > 0,
              let wireIndex = UInt16(exactly: index) else { return }
        itemSelection.requestedCard = (index, item.itemID)
        itemSelection.visible = true
        itemSelection.message = "Waiting for eligible equipment…"
        var packet = PACKET_CZ_REQ_ITEMCOMPOSITION_LIST()
        packet.packetType = HEADER_CZ_REQ_ITEMCOMPOSITION_LIST; packet.index = wireIndex
        sendFoundationPacket(packet)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.itemSelection.requestedCard?.index == index,
                  self.itemSelection.selection == nil, self.itemSelection.pending == nil else { return }
            self.itemSelection.message = "No eligible equipment was returned. Unequip a compatible item with an empty slot, then try again."
        }
    }

    func chooseItemSelection(_ value: Int) {
        guard itemSelection.pending == nil, let selection = itemSelection.selection,
              selection.values.contains(value) else { return }
        switch selection.kind {
        case .identify:
            guard let item = inventory.items[value], !item.isIdentified,
                  let index = UInt16(exactly: value) else { return }
            itemSelection.pending = .init(kind: .identify, index: value, itemID: item.itemID)
            var packet = PACKET_CZ_REQ_ITEMIDENTIFY()
            packet.packetType = HEADER_CZ_REQ_ITEMIDENTIFY; packet.index = index
            sendFoundationPacket(packet)
        case .card:
            guard let card = itemSelection.requestedCard, let item = inventory.items[value],
                  inventory.items[card.index]?.itemID == card.itemID,
                  (inventory.items[card.index]?.amount ?? 0) > 0,
                  item.isIdentified, !item.isEquipped,
                  let cardIndex = UInt16(exactly: card.index), let equipIndex = UInt16(exactly: value) else { return }
            itemSelection.pending = .init(kind: .card, index: value, itemID: item.itemID,
                                          cardIndex: card.index, cardID: card.itemID)
            var packet = PACKET_CZ_REQ_ITEMCOMPOSITION()
            packet.packetType = HEADER_CZ_REQ_ITEMCOMPOSITION
            packet.index_card = cardIndex; packet.index_equip = equipIndex
            sendFoundationPacket(packet)
        case .arrow:
            guard let itemID = UInt32(exactly: value) else { return }
            var packet = PACKET_CZ_REQ_MAKINGARROW()
            packet.packetType = HEADER_CZ_REQ_MAKINGARROW; packet.itemId = itemID
            sendFoundationPacket(packet)
            // This menu has no dedicated success ACK. Inventory/skill packets own results.
            itemSelection = ItemSelectionState()
            return
        }
        itemSelection.message = "Waiting for the server…"
        if let token = itemSelection.pending?.token {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.itemSelection.expire(token: token)
            }
        }
    }

    func closeItemSelection() {
        if itemSelection.pending != nil { itemSelection.visible = false; return }
        if itemSelection.selection?.kind == .identify {
            var packet = PACKET_CZ_REQ_ITEMIDENTIFY()
            packet.packetType = HEADER_CZ_REQ_ITEMIDENTIFY; packet.index = UInt16.max
            sendFoundationPacket(packet)
        } else if itemSelection.selection?.kind == .arrow {
            var packet = PACKET_CZ_REQ_MAKINGARROW()
            packet.packetType = HEADER_CZ_REQ_MAKINGARROW; packet.itemId = 0
            sendFoundationPacket(packet)
        }
        itemSelection = ItemSelectionState()
    }

    func receiveIdentifyResult(_ packet: PACKET_ZC_ACK_ITEMIDENTIFY) {
        let index = Int(packet.index)
        if packet.result == 0 { inventory.items[index]?.isIdentified = true }
        guard itemSelection.pending?.kind == .identify, itemSelection.pending?.index == index else { return }
        itemSelection.pending = nil; itemSelection.selection = nil
        itemSelection.message = packet.result == 0 ? "Item identified." : "The server could not identify this item."
    }

    func receiveCompositionResult(_ packet: PACKET_ZC_ACK_ITEMCOMPOSITION) {
        guard let pending = itemSelection.pending, pending.kind == .card,
              pending.index == Int(packet.equipIndex), pending.cardIndex == Int(packet.cardIndex) else { return }
        if packet.result == 0, let cardID = pending.cardID, let cardIndex = pending.cardIndex,
           inventory.items[pending.index]?.itemID == pending.itemID,
           inventory.items[cardIndex]?.itemID == cardID,
           let slot = inventory.items[pending.index]?.slots.firstIndex(of: 0) {
            // pc_insert_card suppresses its inventory-delete packet (pc_delitem flag1).
            // Apply exactly once, only after matching success ACK; never on button press.
            inventory.items[pending.index]?.slots[slot] = cardID
            inventory.items[cardIndex]?.amount -= 1
            if inventory.items[cardIndex]?.amount == 0 { inventory.items.removeValue(forKey: cardIndex) }
        }
        itemSelection.pending = nil; itemSelection.selection = nil; itemSelection.requestedCard = nil
        itemSelection.message = packet.result == 0 ? "Card inserted." : "The server rejected card insertion."
    }
}
