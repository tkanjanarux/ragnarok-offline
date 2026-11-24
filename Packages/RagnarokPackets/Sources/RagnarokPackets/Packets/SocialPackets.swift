import BinaryIO
import Foundation

public enum SocialPacketError: Error { case invalidText }
public struct ChannelChatRequest: EncodablePacket {
    public enum Channel: Sendable { case party, guild, whisper }
    public let channel: Channel
    public let text: String
    public let recipient: String
    public init(channel: Channel, text: String, recipient: String = "") {
        self.channel = channel; self.text = text; self.recipient = recipient
    }
    public func encode(to encoder: BinaryEncoder) throws {
        guard !text.isEmpty, !text.contains("\0"), text.utf8.count <= 254,
              channel != .whisper || (!recipient.isEmpty && recipient.utf8.count <= 23 && !recipient.contains("\0")) else { throw SocialPacketError.invalidText }
        let header = channel == .party ? 0x108 : channel == .guild ? 0x17e : 0x96
        try encoder.encode(UInt16(header))
        try encoder.encode(UInt16(4 + (channel == .whisper ? 24 : 0) + text.utf8.count + 1))
        if channel == .whisper { try encoder.encode(recipient, lengthOfBytes: 24, encoding: .utf8) }
        try encoder.encode(Array(text.utf8) + [0])
    }
}

public struct FriendInvitation: DecodablePacket {
    public static let size = 34
    public let accountID: UInt32
    public let characterID: UInt32
    public let name: String
    public init(from decoder: BinaryDecoder) throws {
        _ = try decoder.decode(UInt16.self)
        accountID = try decoder.decode(UInt32.self); characterID = try decoder.decode(UInt32.self)
        name = try decoder.decode(String.self, lengthOfBytes: 24, encoding: .utf8)
    }
}
public struct FriendAdded: DecodablePacket {
    public static let size = 36
    public let result: UInt16
    public let accountID: UInt32
    public let characterID: UInt32
    public let name: String
    public init(from decoder: BinaryDecoder) throws {
        _ = try decoder.decode(UInt16.self); result = try decoder.decode(UInt16.self)
        accountID = try decoder.decode(UInt32.self); characterID = try decoder.decode(UInt32.self)
        name = try decoder.decode(String.self, lengthOfBytes: 24, encoding: .utf8)
    }
}
public struct FriendRemoved: DecodablePacket {
    public static let size = 10
    public let accountID: UInt32
    public let characterID: UInt32
    public init(from decoder: BinaryDecoder) throws {
        _ = try decoder.decode(UInt16.self)
        accountID = try decoder.decode(UInt32.self); characterID = try decoder.decode(UInt32.self)
    }
}
public enum FriendRequest: EncodablePacket {
    case invite(name: String), reply(accountID: UInt32, characterID: UInt32, accept: Bool), remove(accountID: UInt32, characterID: UInt32)
    public func encode(to encoder: BinaryEncoder) throws {
        switch self {
        case .invite(let name):
            guard !name.isEmpty, name.utf8.count <= 23, !name.contains("\0") else { throw SocialPacketError.invalidText }
            try encoder.encode(UInt16(0x202)); try encoder.encode(name, lengthOfBytes: 24, encoding: .utf8)
        case .reply(let aid, let cid, let accept):
            try encoder.encode(UInt16(0x208)); try encoder.encode(aid); try encoder.encode(cid); try encoder.encode(UInt32(accept ? 1 : 0))
        case .remove(let aid, let cid):
            try encoder.encode(UInt16(0x203)); try encoder.encode(aid); try encoder.encode(cid)
        }
    }
}
