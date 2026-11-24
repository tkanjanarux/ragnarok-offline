import BinaryIO
public struct AchievementEntry: BinaryDecodable, Sendable {
    public let id: UInt32
    public let completed: Bool
    public let counts: [UInt32]
    public let completedAt: UInt32
    public var rewarded: Bool
    public init(from decoder: BinaryDecoder) throws {
        id = try decoder.decode(UInt32.self); completed = try decoder.decode(UInt8.self) != 0
        counts = try decoder.decode([UInt32].self, count: 10)
        completedAt = try decoder.decode(UInt32.self); rewarded = try decoder.decode(UInt8.self) != 0
    }
}
public struct AchievementRewardResult: DecodablePacket {
    public static let size = 7
    public let result: UInt8
    public let id: UInt32
    public init(from decoder: BinaryDecoder) throws {
        _ = try decoder.decode(UInt16.self); result = try decoder.decode(UInt8.self); id = try decoder.decode(UInt32.self)
    }
}
public struct AttendanceResult: DecodablePacket {
    public static let size = 10
    public let count: UInt32
    public init(from decoder: BinaryDecoder) throws {
        _ = try decoder.decode(UInt16.self); _ = try decoder.decode(UInt32.self); count = try decoder.decode(UInt32.self)
    }
}
public enum RewardRequest: EncodablePacket {
    case achievement(UInt32), openAttendance, claimAttendance
    public func encode(to encoder: BinaryEncoder) throws {
        switch self {
        case .achievement(let id): try encoder.encode(UInt16(0xa25)); try encoder.encode(id)
        case .openAttendance: try encoder.encode(UInt16(0xa68)); try encoder.encode(UInt8(5))
        case .claimAttendance: try encoder.encode(UInt16(0xaef))
        }
    }
}
