import BinaryIO
public enum VendingRequest: EncodablePacket {
    public struct Entry: Sendable { public let index: UInt16, amount: UInt16; public let price: UInt32
        public init(index: UInt16, amount: UInt16, price: UInt32) { self.index = index; self.amount = amount; self.price = price }
    }
    case browse(UInt32), buy(UInt32, UInt32, UInt16, UInt16), open(String, [Entry]), cancel, close
    public func encode(to e: BinaryEncoder) throws {
        switch self {
        case .browse(let id): try e.encode(UInt16(0x130)); try e.encode(id)
        case let .buy(owner, shop, index, amount):
            try e.encode(UInt16(0x801)); try e.encode(UInt16(16)); try e.encode(owner); try e.encode(shop); try e.encode(amount); try e.encode(index)
        case let .open(name, items):
            guard !name.isEmpty, name.utf8.count < 80, !name.contains("\0"), !items.isEmpty, items.count <= 12,
                  Set(items.map(\.index)).count == items.count, items.allSatisfy({ $0.amount > 0 && $0.price > 0 }) else { throw SocialPacketError.invalidText }
            try e.encode(UInt16(0x1b2)); try e.encode(UInt16(85 + items.count * 8)); try e.encode(name, lengthOfBytes: 80, encoding: .utf8); try e.encode(UInt8(1))
            for item in items { try e.encode(item.index); try e.encode(item.amount); try e.encode(item.price) }
        case .cancel:
            try e.encode(UInt16(0x1b2)); try e.encode(UInt16(85)); try e.encode([UInt8](repeating: 0, count: 81))
        case .close: try e.encode(UInt16(0x12e))
        }
    }
}
