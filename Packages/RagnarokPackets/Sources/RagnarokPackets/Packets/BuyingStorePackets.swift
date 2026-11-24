import BinaryIO
public struct BuyingStoreOpened: DecodablePacket {
    public static let size = 3
    public let slots: UInt8
    public init(from d: BinaryDecoder) throws { _ = try d.decode(UInt16.self); slots = try d.decode(UInt8.self) }
}
public struct BuyingStoreRejected: DecodablePacket {
    public static let size = 8
    public let result: UInt16, weight: UInt32
    public init(from d: BinaryDecoder) throws { _ = try d.decode(UInt16.self); result = try d.decode(UInt16.self); weight = try d.decode(UInt32.self) }
}
public struct BuyingStoreEnded: DecodablePacket {
    public static let size = 4
    public let reason: UInt16
    public init(from d: BinaryDecoder) throws { _ = try d.decode(UInt16.self); reason = try d.decode(UInt16.self) }
}
public struct BuyingStoreSold: DecodablePacket {
    public static let size = 10
    public let index: UInt16, amount: UInt16, price: UInt32
    public init(from d: BinaryDecoder) throws { _ = try d.decode(UInt16.self); index = try d.decode(UInt16.self); amount = try d.decode(UInt16.self); price = try d.decode(UInt32.self) }
}
public enum BuyingStoreRequest: EncodablePacket {
    case open(String, UInt32, [PACKET_CZ_REQ_OPEN_BUYING_STORE_sub]), cancel, close, browse(UInt32)
    case sell(owner: UInt32, store: UInt32, index: UInt16, item: UInt32, amount: UInt16)
    public func encode(to e: BinaryEncoder) throws {
        switch self {
        case let .open(name, limit, items):
            guard !name.isEmpty, name.utf8.count < 80, !name.contains("\0"), limit > 0, !items.isEmpty, items.count <= 5,
                  Set(items.map(\.itemId)).count == items.count else { throw SocialPacketError.invalidText }
            try e.encode(UInt16(0x811)); try e.encode(UInt16(89 + items.count * 10)); try e.encode(limit); try e.encode(UInt8(1))
            try e.encode(name, lengthOfBytes: 80, encoding: .utf8); try e.encode(items)
        case .cancel:
            try e.encode(UInt16(0x811)); try e.encode(UInt16(89)); try e.encode([UInt8](repeating: 0, count: 85))
        case .close: try e.encode(UInt16(0x815))
        case .browse(let id): try e.encode(UInt16(0x817)); try e.encode(id)
        case let .sell(owner, store, index, item, amount):
            try e.encode(UInt16(0x819)); try e.encode(UInt16(20)); try e.encode(owner); try e.encode(store); try e.encode(index); try e.encode(item); try e.encode(amount)
        }
    }
}
