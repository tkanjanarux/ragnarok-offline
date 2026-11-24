//
//  InventoryItem.swift
//  RagnarokModels
//
//  Created by Leon Li on 2025/4/15.
//

import RagnarokConstants
import RagnarokPackets

public struct InventoryItem: Sendable {
    public var index: Int
    public var itemID: Int
    public var type: ItemType
    public var amount: Int
    public var location: EquipPositions
    public var equippedLocation: EquipPositions
    public var slots: [Int]
    public var isIdentified = false
    public var refineLevel = 0
    public var isDamaged = false
    public var enchantGrade: Int?
    public var hasRandomOptions: Bool?
    public struct Option: Equatable, Sendable {
        public var id: Int; public var value: Int; public var parameter: Int
        public init(_ source: ItemOptions) { id = Int(source.index); value = Int(source.value); parameter = Int(source.param) }
    }
    public var randomOptions: [Option] = []

    public var isUsable: Bool {
        switch type {
        case .healing, .usable, .delayconsume, .cash: true
        default: false
        }
    }

    public var isEquippable: Bool {
        switch type {
        case .weapon, .armor, .shadowgear, .petegg, .petarmor, .ammo: true
        default: false
        }
    }

    public var isEquipped: Bool {
        !equippedLocation.isEmpty && type != .card
    }

    public var isEtc: Bool {
        switch type {
        case .etc, .card: true
        default: false
        }
    }

    public init() {
        index = 0
        itemID = 0
        type = .etc
        amount = 0
        location = EquipPositions(rawValue: 0)
        equippedLocation = EquipPositions(rawValue: 0)
        slots = [0, 0, 0, 0]
    }

    public init(from item: NORMALITEM_INFO) {
        isIdentified = item.Flag & 1 != 0
        index = Int(item.index)
        itemID = Int(item.ITID)
        type = ItemType(rawValue: Int(item.type)) ?? .etc
        amount = Int(item.count)
        location = EquipPositions(rawValue: 0)
        equippedLocation = EquipPositions(rawValue: Int(item.WearState))
        slots = item.slot.card.map(Int.init)
    }

    public init(from item: EQUIPITEM_INFO) {
        isIdentified = item.Flag & 1 != 0
        isDamaged = item.Flag & 2 != 0
        refineLevel = Int(item.RefiningLevel)
        enchantGrade = Int(item.grade)
        hasRandomOptions = item.option_data.contains { $0.index != 0 }
        randomOptions = item.option_data.filter { $0.index != 0 }.map(Option.init)
        index = Int(item.index)
        itemID = Int(item.ITID)
        type = ItemType(rawValue: Int(item.type)) ?? .etc
        amount = 1
        location = EquipPositions(rawValue: Int(item.location))
        equippedLocation = EquipPositions(rawValue: Int(item.WearState))
        slots = item.slot.card.map(Int.init)
    }
}

extension InventoryItem: Comparable {
    public static func < (lhs: InventoryItem, rhs: InventoryItem) -> Bool {
        lhs.index < rhs.index
    }
}
