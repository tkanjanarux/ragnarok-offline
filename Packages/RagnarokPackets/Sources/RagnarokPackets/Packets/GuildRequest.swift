import BinaryIO
public enum GuildRequest: EncodablePacket {
    case access, page(UInt32), create(UInt32, String), invite(String), reply(UInt32, Bool)
    case remove(guild: UInt32, account: UInt32, character: UInt32, reason: String, kick: Bool)
    case disband(String), notice(UInt32, String, String), memberPosition(UInt32, UInt32, Int32)
    case position(Int32, Int32, Int32, String)
    case alliance(UInt32, UInt32, UInt32), allianceReply(UInt32, Bool), removeRelation(UInt32, UInt32)
    case emblem(UInt32), uploadEmblem([UInt8])
    public func encode(to encoder: BinaryEncoder) throws {
        func validate(_ text: String, _ limit: Int) throws {
            guard text.utf8.count < limit, !text.contains("\0") else { throw SocialPacketError.invalidText }
        }
        switch self {
        case let .alliance(target, account, character):
            try encoder.encode(UInt16(0x170)); try encoder.encode(target); try encoder.encode(account); try encoder.encode(character)
        case let .allianceReply(account, accept):
            try encoder.encode(UInt16(0x172)); try encoder.encode(account); try encoder.encode(UInt32(accept ? 1 : 0))
        case let .removeRelation(id, relation):
            guard relation <= 1 else { throw SocialPacketError.invalidText }
            try encoder.encode(UInt16(0x183)); try encoder.encode(id); try encoder.encode(relation)
        case .emblem(let id): try encoder.encode(UInt16(0x151)); try encoder.encode(id)
        case .uploadEmblem(let bytes):
            guard !bytes.isEmpty, bytes.count <= 2048 else { throw SocialPacketError.invalidText }
            try encoder.encode(UInt16(0x153)); try encoder.encode(UInt16(bytes.count + 4)); try encoder.encode(bytes)
        case .access: try encoder.encode(UInt16(0x14d))
        case .page(let page): try encoder.encode(UInt16(0x14f)); try encoder.encode(page)
        case let .create(account, name):
            try validate(name,24); try encoder.encode(UInt16(0x165)); try encoder.encode(account); try encoder.encode(name, lengthOfBytes: 24, encoding: .utf8)
        case .invite(let name):
            try validate(name,24); try encoder.encode(UInt16(0x916)); try encoder.encode(name, lengthOfBytes: 24, encoding: .utf8)
        case let .reply(id, accept): try encoder.encode(UInt16(0x16b)); try encoder.encode(id); try encoder.encode(UInt32(accept ? 1 : 0))
        case let .remove(guild, account, character, reason, kick):
            try validate(reason,40); try encoder.encode(UInt16(kick ? 0x15b : 0x159))
            try encoder.encode(guild); try encoder.encode(account); try encoder.encode(character); try encoder.encode(reason, lengthOfBytes: 40, encoding: .utf8)
        case .disband(let name): try validate(name,40); try encoder.encode(UInt16(0x15d)); try encoder.encode(name, lengthOfBytes: 40, encoding: .utf8)
        case let .notice(id, title, text):
            try validate(title,60); try validate(text,120); try encoder.encode(UInt16(0x16e)); try encoder.encode(id)
            try encoder.encode(title, lengthOfBytes: 60, encoding: .utf8); try encoder.encode(text, lengthOfBytes: 120, encoding: .utf8)
        case let .memberPosition(account, character, position):
            try encoder.encode(UInt16(0x155)); try encoder.encode(UInt16(16)); try encoder.encode(account); try encoder.encode(character); try encoder.encode(position)
        case let .position(id, mode, tax, name):
            try validate(name,24); try encoder.encode(UInt16(0x161)); try encoder.encode(UInt16(44)); try encoder.encode(id)
            try encoder.encode(mode); try encoder.encode(Int32(0)); try encoder.encode(tax); try encoder.encode(name, lengthOfBytes: 24, encoding: .utf8)
        }
    }
}
public struct GuildMemberStatus: DecodablePacket {
    public static let size = 20
    public let account: UInt32
    public let character: UInt32
    public let online: UInt32
    public let gender: UInt16
    public let hair: UInt16
    public init(from decoder: BinaryDecoder) throws {
        _ = try decoder.decode(UInt16.self); account = try decoder.decode(UInt32.self); character = try decoder.decode(UInt32.self)
        online = try decoder.decode(UInt32.self); gender = try decoder.decode(UInt16.self); hair = try decoder.decode(UInt16.self)
        _ = try decoder.decode(UInt16.self) // hair color
    }
}

/// The legacy map-server reply has a 12-byte header and binary zlib bytes.
/// It is distinct from the newer web-emblem 0xb36 reply.
public struct GuildEmblemPacket: DecodablePacket {
    public static let size = -1
    public let guildID: UInt32
    public let version: UInt32
    public let compressed: [UInt8]
    public init(from decoder: BinaryDecoder) throws {
        let type = try decoder.decode(Int16.self)
        let length = Int(try decoder.decode(UInt16.self))
        guard type == 0x152, (13...2060).contains(length) else { throw PacketDecodingError.invalidPacketLength(type, length) }
        guildID = try decoder.decode(UInt32.self); version = try decoder.decode(UInt32.self)
        compressed = try decoder.decode([UInt8].self, count: length - 12)
    }
}
