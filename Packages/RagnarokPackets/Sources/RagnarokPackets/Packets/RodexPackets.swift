import BinaryIO

/// PACKETVER RE 20211103. Preserve mail IDs as 64-bit values, not list offsets.
public struct RodexList: DecodablePacket {
    public static let size = -1
    public struct Entry: Sendable {
        public let tab: UInt8, id: UInt64, read: Bool, attachments: UInt8, sender: String, expires: UInt32, title: String
    }
    public let entries: [Entry]
    public init(from d: BinaryDecoder) throws {
        let op = try d.decode(Int16.self); let length = Int(try d.decode(UInt16.self))
        guard length >= 5 else { throw PacketDecodingError.invalidPacketLength(op, length) }
        _ = try d.decode(UInt8.self); var remaining = length - 5; var rows: [Entry] = []
        while remaining > 0 {
            guard remaining >= 41 else { throw PacketDecodingError.invalidPacketLength(op, length) }
            let tab = try d.decode(UInt8.self), id = try d.decode(UInt64.self)
            let read = try d.decode(UInt8.self), flags = try d.decode(UInt8.self)
            let sender = try d.decode(String.self, lengthOfBytes: 24, encoding: .utf8)
            let expires = try d.decode(UInt32.self), titleLength = Int(try d.decode(UInt16.self))
            guard titleLength > 0, titleLength <= 40, titleLength <= remaining - 41 else { throw PacketDecodingError.invalidPacketLength(op, length) }
            let title = try d.decode(String.self, lengthOfBytes: titleLength, encoding: .utf8)
            rows.append(.init(tab: tab, id: id, read: read != 0, attachments: flags, sender: sender, expires: expires, title: title))
            remaining -= 41 + titleLength
        }
        entries = rows
    }
}
public struct RodexRead: DecodablePacket {
    public static let size = -1
    public let tab: UInt8, id: UInt64, text: String
    public var zeny: UInt64
    public var items: [PACKET_ZC_ACK_READ_RODEX_SUB]
    public init(from d: BinaryDecoder) throws {
        let op = try d.decode(Int16.self), length = Int(try d.decode(UInt16.self))
        guard length >= 24 else { throw PacketDecodingError.invalidPacketLength(op, length) }
        tab = try d.decode(UInt8.self); id = try d.decode(UInt64.self)
        let textLength = Int(try d.decode(UInt16.self)); zeny = try d.decode(UInt64.self)
        let count = Int(try d.decode(UInt8.self))
        guard count <= 5, textLength > 0, textLength <= 500,
              24 + textLength + count * PACKET_ZC_ACK_READ_RODEX_SUB.size == length else { throw PacketDecodingError.invalidPacketLength(op, length) }
        text = try d.decode(String.self, lengthOfBytes: textLength, encoding: .utf8)
        items = try d.decode([PACKET_ZC_ACK_READ_RODEX_SUB].self, count: count)
    }
}
public enum RodexRequest: EncodablePacket {
    case list, close, begin(String), check(String), cancel
    case read(UInt64, UInt8), claim(UInt64, UInt8, Bool), delete(UInt64, UInt8)
    case attach(UInt16, UInt16), remove(UInt16, UInt16)
    case send(receiver: String, sender: String, character: Int32, title: String, text: String, zeny: UInt64)
    public func encode(to e: BinaryEncoder) throws {
        func fixedName(_ value: String) throws {
            guard value.utf8.count <= 23, !value.contains("\0") else { throw SocialPacketError.invalidText }
            try e.encode(value, lengthOfBytes: 24, encoding: .utf8)
        }
        switch self {
        case .list: try e.encode(UInt16(0xac1)); try e.encode(UInt64(0)); try e.encode([UInt8](repeating: 0, count: 16))
        case .close: try e.encode(UInt16(0x9e9))
        case .cancel: try e.encode(UInt16(0xa03))
        case .begin(let name): try e.encode(UInt16(0xa08)); try fixedName(name)
        case .check(let name): try e.encode(UInt16(0xb97)); try fixedName(name); try e.encode(UInt8(0))
        case let .read(id, tab): try e.encode(UInt16(0x9ea)); try e.encode(tab); try e.encode(id)
        case let .delete(id, tab): try e.encode(UInt16(0x9f5)); try e.encode(tab); try e.encode(id)
        case let .claim(id, tab, items): try e.encode(UInt16(items ? 0x9f3 : 0x9f1)); try e.encode(id); try e.encode(tab)
        case let .attach(index, count): try e.encode(UInt16(0xa04)); try e.encode(index); try e.encode(count)
        case let .remove(index, count): try e.encode(UInt16(0xa06)); try e.encode(index); try e.encode(count)
        case let .send(receiver, sender, character, title, text, zeny):
            guard !title.isEmpty, title.utf8.count < 40, text.utf8.count < 500,
                  !title.contains("\0"), !text.contains("\0"), zeny <= 2_000_000_000 else { throw SocialPacketError.invalidText }
            try e.encode(UInt16(0xa6e)); try e.encode(UInt16(70 + title.utf8.count + text.utf8.count))
            try fixedName(receiver); try fixedName(sender); try e.encode(zeny)
            try e.encode(UInt16(title.utf8.count + 1)); try e.encode(UInt16(text.utf8.count + 1)); try e.encode(character)
            try e.encode(title + "\0" + text + "\0", encoding: .utf8)
        }
    }
}
