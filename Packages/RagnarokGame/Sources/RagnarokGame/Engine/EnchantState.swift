import Foundation
import RagnarokModels
import RagnarokPackets

// Public server recipe data; authorization and results always come from the server.
struct EnchantCatalog: Decodable {
    struct Material: Decodable { var id: Int; var amount: Int }
    struct Choice: Decodable { var item: Int; var result: Int?; var price: Int; var materials: [Material] }
    struct Slot: Decodable { var id: Int; var price: Int; var materials: [Material]; var grades: [Int]; var perfect: [Choice]; var upgrades: [Choice] }
    struct Reset: Decodable { var price: Int; var chance: Int; var materials: [Material] }
    struct Recipe: Decodable { var id: UInt64; var targets: [Int]; var refine: Int; var grade: Int; var allowOptions: Bool; var order: [Int]; var slots: [Slot]; var reset: Reset? }
    var cardSlots: [String: Int]
    var recipes: [Recipe]
    static let shared: EnchantCatalog? = {
        guard let url = Bundle.module.url(forResource: "EnchantCatalog", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }()
}

struct EnchantState {
    struct Action: Identifiable {
        enum Kind: String { case random, perfect, upgrade, reset }
        var kind: Kind; var slot: Int; var item: Int = 0; var result: Int = 0
        var price: Int; var materials: [EnchantCatalog.Material]
        var id: String { "\(kind.rawValue):\(slot):\(item)" }
    }
    struct Pending { let token = UUID(); var index: Int; var itemID: Int; var originalSlots: [Int]; var cardSlots: Int; var action: Action }
    var visible = false
    var group: UInt64?
    var selected: Int?
    var pending: Pending?
    var message: String?
    var recipe: EnchantCatalog.Recipe? { EnchantCatalog.shared?.recipes.first { $0.id == group } }

    func actions(for item: InventoryItem, registered: Bool) -> [Action] {
        guard let recipe, !registered, !item.isEquipped, item.isIdentified, !item.isDamaged,
              recipe.targets.contains(item.itemID), item.refineLevel >= recipe.refine,
              let grade = item.enchantGrade, grade >= recipe.grade,
              item.slots.count == 4, let count = EnchantCatalog.shared?.cardSlots[String(item.itemID)], (0...4).contains(count) else { return [] }
        var result: [Action] = []
        if recipe.allowOptions || item.hasRandomOptions == false {
            if let next = recipe.order.first(where: { (0..<4).contains($0) && item.slots[$0] == 0 }), next >= count,
               let slot = recipe.slots.first(where: { $0.id == next }) {
                if slot.grades.contains(grade) { result.append(.init(kind: .random, slot: next, price: slot.price, materials: slot.materials)) }
                result += slot.perfect.map { .init(kind: .perfect, slot: next, item: $0.item, price: $0.price, materials: $0.materials) }
            }
            for slot in recipe.slots where (count..<4).contains(slot.id) {
                result += slot.upgrades.filter { $0.item == item.slots[slot.id] }.map {
                    .init(kind: .upgrade, slot: slot.id, item: $0.item, result: $0.result ?? 0, price: $0.price, materials: $0.materials)
                }
            }
        }
        if let reset = recipe.reset, reset.chance > 0, item.slots.dropFirst(count).contains(where: { $0 != 0 }) {
            result.append(.init(kind: .reset, slot: count, price: reset.price, materials: reset.materials))
        }
        return result
    }

    mutating func receive(_ packet: PACKET_ZC_RESPONSE_ENCHANT, inventory: inout Inventory) {
        guard let request = pending else { return }
        pending = nil; group = nil
        guard packet.msgId == 3857 else { message = "Enchanting failed. Check your items and speak to the enchanter again."; return }
        guard var item = inventory.items[request.index], item.itemID == request.itemID, item.slots == request.originalSlots else {
            message = "The item changed. Reconnect to refresh your inventory."; return
        }
        switch request.action.kind {
        case .reset:
            guard packet.ITID == 0 else { message = "Unexpected result. Reconnect to refresh your inventory."; return }
            for index in request.cardSlots..<4 { item.slots[index] = 0 }
        case .perfect, .upgrade, .random:
            let expected = request.action.kind == .perfect ? request.action.item : request.action.result
            guard packet.ITID > 0, expected == 0 || Int(packet.ITID) == expected else {
                message = "Unexpected result. Reconnect to refresh your inventory."; return
            }
            item.slots[request.action.slot] = Int(packet.ITID)
        }
        inventory.items[request.index] = item
        message = "Enchanting succeeded. Speak to the enchanter again to continue."
    }
}

extension PlaySession {
    func requestEnchant(_ action: EnchantState.Action) {
        guard enchant.pending == nil, !buyingStore.busy, !vending.active, vending.purchase == nil, !rodex.busy,
              !trade.active, trade.waiting == nil, bank.pending == nil, cart.pending == nil, refine.pending == nil,
              itemSelection.pending == nil, equipmentSwitch.pending == nil,
              let group = enchant.group, let wireGroup = Int64(exactly: group), let index = enchant.selected,
              let wireIndex = Int16(exactly: index), let item = inventory.items[index],
              let valid = enchant.actions(for: item, registered: equipmentSwitch.entries[index] != nil).first(where: { $0.id == action.id }),
              playerStatus.zeny >= valid.price,
              valid.materials.allSatisfy({ cost in inventory.items.values.contains { $0.itemID == cost.id && $0.amount >= cost.amount } }),
              let count = EnchantCatalog.shared?.cardSlots[String(item.itemID)] else { return }
        enchant.pending = .init(index: index, itemID: item.itemID, originalSlots: item.slots, cardSlots: count, action: valid)
        enchant.message = "Waiting for the server…"
        switch valid.kind {
        case .random:
            var p = PACKET_CZ_REQUEST_RANDOM_ENCHANT(); p.packetType = HEADER_CZ_REQUEST_RANDOM_ENCHANT; p.enchant_group = wireGroup; p.index = wireIndex; sendFoundationPacket(p)
        case .perfect:
            var p = PACKET_CZ_REQUEST_PERFECT_ENCHANT(); p.packetType = HEADER_CZ_REQUEST_PERFECT_ENCHANT; p.enchant_group = wireGroup; p.index = wireIndex; p.ITID = UInt32(valid.item); sendFoundationPacket(p)
        case .upgrade:
            var p = PACKET_CZ_REQUEST_UPGRADE_ENCHANT(); p.packetType = HEADER_CZ_REQUEST_UPGRADE_ENCHANT; p.enchant_group = wireGroup; p.index = wireIndex; p.slot = Int16(valid.slot); sendFoundationPacket(p)
        case .reset:
            var p = PACKET_CZ_REQUEST_RESET_ENCHANT(); p.packetType = HEADER_CZ_REQUEST_RESET_ENCHANT; p.enchant_group = wireGroup; p.index = wireIndex; sendFoundationPacket(p)
        }
        let token = enchant.pending?.token
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, let token, self.enchant.pending?.token == token else { return }
            self.enchant.message = "No result received. Reconnect before trying again."
        }
    }
    func closeEnchant() {
        enchant.visible = false
        guard enchant.pending == nil else { return }
        var p = PACKET_CZ_CLOSE_UI_ENCHANT(); p.packetType = HEADER_CZ_CLOSE_UI_ENCHANT; sendFoundationPacket(p)
        enchant.group = nil
    }
}
