import BinaryIO

public struct PACKET_ZC_ALL_ACH_LIST: DecodablePacket {
    public static let size = -1
    public let points: UInt32
    public let rank: UInt16
    public let currentRankPoints: UInt32
    public let nextRankPoints: UInt32
    public let entries: [AchievementEntry]
    public init(from decoder: BinaryDecoder) throws {
        _ = try decoder.decode(UInt16.self)
        let length = Int(try decoder.decode(UInt16.self))
        guard length >= 22, (length - 22) % 50 == 0 else { throw PacketDecodingError.invalidPacketLength(0xa23, length) }
        let count = Int(try decoder.decode(UInt32.self))
        guard count == (length - 22) / 50 else { throw PacketDecodingError.invalidPacketLength(0xa23, length) }
        points = try decoder.decode(UInt32.self); rank = try decoder.decode(UInt16.self)
        currentRankPoints = try decoder.decode(UInt32.self); nextRankPoints = try decoder.decode(UInt32.self)
        entries = try decoder.decode([AchievementEntry].self, count: count)
    }
}
