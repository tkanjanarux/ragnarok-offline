import Foundation
import RagnarokPackets

struct RefineState {
    struct Material: Identifiable {
        var id: UInt32
        var chance: Int
        var zeny: Int
    }
    var visible = false
    var authorized = false
    var selectedIndex: Int?
    var selectedItemID: Int?
    var selectionToken = UUID()
    var materials: [Material] = []
    var blessingCount = 0
    var pending: UUID?
    var message: String?

    mutating func receive(_ packet: PACKET_ZC_REFINING_MATERIAL_LIST) {
        guard authorized, Int(packet.itemIndex) == selectedIndex else { return }
        materials = packet.req.filter { $0.itemId > 0 && $0.zeny >= 0 && (0...100).contains($0.chance) }
            .map { .init(id: $0.itemId, chance: Int($0.chance), zeny: Int($0.zeny)) }
        blessingCount = max(0, Int(packet.blacksmithBlessing))
        if pending == nil { message = materials.isEmpty ? "This item cannot be refined further." : nil }
    }
}

extension PlaySession {
    func selectRefineItem(_ index: Int) {
        guard refine.authorized, refine.pending == nil, let item = inventory.items[index],
              item.isIdentified, !item.isDamaged, let wireIndex = Int16(exactly: index) else { return }
        refine.selectedIndex = index; refine.selectedItemID = item.itemID
        let selectionToken = UUID(); refine.selectionToken = selectionToken
        refine.materials = []; refine.message = "Loading refining materials…"
        var packet = PACKET_CZ_REFINING_SELECT_ITEM()
        packet.packetType = HEADER_CZ_REFINING_SELECT_ITEM; packet.index = wireIndex
        sendFoundationPacket(packet)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.refine.selectionToken == selectionToken, self.refine.selectedIndex == index, self.refine.materials.isEmpty,
                  self.refine.message == "Loading refining materials…" else { return }
            self.refine.message = "No refining options returned. Select another item or speak to the refiner again."
        }
    }
    func requestRefine(material: UInt32, blessing: Bool) {
        guard !basicTransactions.busy else { return }
        guard enchant.pending == nil, !buyingStore.busy, !vending.active, vending.purchase == nil, !rodex.busy, !trade.active, trade.waiting == nil else { return }
        guard refine.authorized, refine.pending == nil, cart.pending == nil, itemSelection.pending == nil,
              let index = refine.selectedIndex, inventory.items[index]?.itemID == refine.selectedItemID,
              let wireIndex = Int16(exactly: index),
              let cost = refine.materials.first(where: { $0.id == material }),
              playerStatus.zeny >= cost.zeny,
              inventory.items.values.contains(where: { $0.itemID == Int(material) && $0.amount > 0 }),
              !blessing || (refine.blessingCount > 0 && inventory.items.values.contains(where: { $0.itemID == 6635 && $0.amount >= refine.blessingCount })) else { return }
        let token = UUID(); refine.pending = token; refine.message = "Waiting for the server…"
        var packet = PACKET_CZ_REQ_REFINING()
        packet.packetType = HEADER_CZ_REQ_REFINING; packet.index = wireIndex
        packet.itemId = material; packet.blacksmithBlessing = blessing ? 1 : 0
        sendFoundationPacket(packet)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.refine.pending == token else { return }
            self.refine.message = "No server result. Reconnect before trying again."
        }
    }
    func closeRefine() {
        var packet = PACKET_CZ_CLOSE_REFINING_UI(); packet.packetType = HEADER_CZ_CLOSE_REFINING_UI
        sendFoundationPacket(packet)
        refine.visible = false; refine.authorized = false
    }
    func receiveRefineResult(_ packet: PACKET_ZC_ACK_ITEMREFINING) {
        let index = Int(packet.index)
        if packet.result == 0 || packet.result == 2 { inventory.items[index]?.refineLevel = Int(packet.value) }
        guard refine.selectedIndex == index else { return }
        refine.pending = nil; refine.materials = []
        switch packet.result {
        case 0: refine.message = "Refining succeeded: +\(packet.value)."
        case 1: refine.message = "Refining failed. The item was destroyed."
        case 2: refine.message = "Refining failed: downgraded to +\(packet.value)."
        default: refine.message = "Refining failed. The item was preserved."
        }
        // Item removal, material consumption and zeny are separate authoritative updates.
    }
}
