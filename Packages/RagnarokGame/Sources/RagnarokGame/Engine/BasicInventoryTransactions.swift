import RagnarokModels

/// These legacy transactions carry no request ID. Keep a single request in flight
/// until its source delta/result arrives. A timeout cannot establish rejection.
struct BasicInventoryTransactions {
    enum Shop { case buy, sell }
    enum Direction { case deposit, withdraw }
    struct Transfer {
        let direction: Direction
        let index: Int
        let amount: Int
    }

    private(set) var shop: Shop?
    private(set) var transfer: Transfer?
    private(set) var closingStorage = false
    var busy: Bool { shop != nil || transfer != nil || closingStorage }

    static func canSell(_ sales: [NPCShopSale], offered: Set<Int>, inventory: Inventory) -> Bool {
        guard !sales.isEmpty, Set(sales.map(\.index)).count == sales.count else { return false }
        return sales.allSatisfy { sale in
            offered.contains(sale.index) && (2...Int(UInt16.max)).contains(sale.index)
                && (1...Int(UInt16.max)).contains(sale.amount)
                && (inventory.items[sale.index]?.amount ?? 0) >= sale.amount
        }
    }

    mutating func beginShop(_ kind: Shop) -> Bool {
        guard !busy else { return false }
        shop = kind
        return true
    }

    mutating func receiveShop(_ kind: Shop) {
        if shop == kind { shop = nil }
    }

    mutating func beginStorage(_ direction: Direction, item: InventoryItem, amount: Int) -> Bool {
        let minimumIndex = direction == .deposit ? 2 : 1
        guard !busy, (minimumIndex...Int(UInt16.max)).contains(item.index),
              amount > 0, amount <= Int(Int32.max), amount <= item.amount else { return false }
        transfer = Transfer(direction: direction, index: item.index, amount: amount)
        return true
    }

    mutating func receiveStorage(_ direction: Direction, index: Int, amount: Int) {
        guard let transfer, transfer.direction == direction, transfer.index == index,
              amount == 0 || amount == transfer.amount else { return }
        self.transfer = nil
    }

    mutating func beginStorageClose() -> Bool {
        guard !closingStorage else { return false }
        closingStorage = true
        return true
    }

    mutating func storageClosed() {
        transfer = nil
        closingStorage = false
    }
}
