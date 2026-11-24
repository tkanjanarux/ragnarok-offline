import BinaryIO
public struct MercenaryInfo: DecodablePacket {
    public static let size = 80
    public let id: UInt32
    public let combat: [UInt16]
    public let name: String
    public let level: UInt16
    public var hp: UInt32
    public var maxHP: UInt32
    public var sp: UInt32
    public var maxSP: UInt32
    public let expires: UInt32
    public var faith: UInt16
    public let calls: UInt32
    public var kills: UInt32
    public let range: UInt16
    public init(from decoder: BinaryDecoder) throws {
        _ = try decoder.decode(UInt16.self); id = try decoder.decode(UInt32.self)
        combat = try decoder.decode([UInt16].self, count: 8)
        name = try decoder.decode(String.self, lengthOfBytes: 24, encoding: .utf8); level = try decoder.decode(UInt16.self)
        hp = try decoder.decode(UInt32.self); maxHP = try decoder.decode(UInt32.self)
        sp = try decoder.decode(UInt32.self); maxSP = try decoder.decode(UInt32.self)
        expires = try decoder.decode(UInt32.self); faith = try decoder.decode(UInt16.self)
        calls = try decoder.decode(UInt32.self); kills = try decoder.decode(UInt32.self); range = try decoder.decode(UInt16.self)
    }
}
public struct MercenaryParameter: DecodablePacket {
    public static let size = 8
    public let type: UInt16
    public let value: UInt32
    public init(from decoder: BinaryDecoder) throws {
        _ = try decoder.decode(UInt16.self); type = try decoder.decode(UInt16.self); value = try decoder.decode(UInt32.self)
    }
}
public struct MercenarySkills: DecodablePacket {
    public static let size = -1
    public let skills: [PACKET_ZC_HOSKILLINFO_LIST_sub]
    public init(from decoder: BinaryDecoder) throws {
        _ = try decoder.decode(UInt16.self); let length = Int(try decoder.decode(UInt16.self))
        guard length >= 4, (length - 4) % 37 == 0 else { throw PacketDecodingError.invalidPacketLength(0x29d, length) }
        skills = try decoder.decode([PACKET_ZC_HOSKILLINFO_LIST_sub].self, count: (length - 4) / 37)
    }
}
public enum FollowerRequest: EncodablePacket {
    case homunculus(UInt8), dismissMercenary, renameHomunculus(String), follow(UInt32), attack(UInt32, UInt32), upgrade(UInt16), autoFeed(Bool)
    public func encode(to encoder: BinaryEncoder) throws {
        switch self {
        case .homunculus(let command): try encoder.encode(UInt16(0x22d)); try encoder.encode(UInt16(0)); try encoder.encode(command)
        case .dismissMercenary: try encoder.encode(UInt16(0x29f)); try encoder.encode(UInt8(2))
        case .renameHomunculus(let name):
            guard !name.isEmpty, name.utf8.count <= 23, !name.contains("\0") else { throw SocialPacketError.invalidText }
            try encoder.encode(UInt16(0x231)); try encoder.encode(name, lengthOfBytes: 24, encoding: .utf8)
        case .follow(let id): try encoder.encode(UInt16(0x234)); try encoder.encode(id)
        case .attack(let id, let target): try encoder.encode(UInt16(0x233)); try encoder.encode(id); try encoder.encode(target); try encoder.encode(UInt8(0))
        case .upgrade(let id): try encoder.encode(UInt16(0x112)); try encoder.encode(id)
        case .autoFeed(let enabled): try encoder.encode(UInt16(0x2d8)); try encoder.encode(UInt32(3)); try encoder.encode(UInt32(enabled ? 1 : 0))
        }
    }
}
