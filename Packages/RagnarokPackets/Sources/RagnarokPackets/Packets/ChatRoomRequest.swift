import BinaryIO
public enum ChatRoomRequest: EncodablePacket {
    case configure(title: String, limit: UInt16, password: String, editing: Bool)
    case join(UInt32, String), leave, kick(String), owner(String)
    public func encode(to encoder: BinaryEncoder) throws {
        switch self {
        case let .configure(title, limit, password, editing):
            guard !title.isEmpty, title.utf8.count <= 60, !title.contains("\0"), (2...20).contains(limit), password.utf8.count <= 7, !password.contains("\0") else { throw SocialPacketError.invalidText }
            try encoder.encode(UInt16(editing ? 0xde : 0xd5)); try encoder.encode(UInt16(15 + title.utf8.count))
            try encoder.encode(limit); try encoder.encode(UInt8(password.isEmpty ? 1 : 0))
            try encoder.encode(password, lengthOfBytes: 8, encoding: .utf8); try encoder.encode(Array(title.utf8))
        case let .join(id, password):
            guard password.utf8.count <= 7, !password.contains("\0") else { throw SocialPacketError.invalidText }
            try encoder.encode(UInt16(0xd9)); try encoder.encode(id); try encoder.encode(password, lengthOfBytes: 8, encoding: .utf8)
        case .leave: try encoder.encode(UInt16(0xe3))
        case let .kick(name), let .owner(name):
            guard name.utf8.count <= 23, !name.isEmpty, !name.contains("\0") else { throw SocialPacketError.invalidText }
            if case .owner = self { try encoder.encode(UInt16(0xe0)); try encoder.encode(UInt32(0)) }
            else { try encoder.encode(UInt16(0xe2)) }
            try encoder.encode(name, lengthOfBytes: 24, encoding: .utf8)
        }
    }
}
