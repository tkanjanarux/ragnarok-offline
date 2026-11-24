import BinaryIO

public struct PACKET_ZC_ACH_UPDATE: DecodablePacket {
    public static let size = 66
    public let points: UInt32
    public let rank: UInt16
    public let currentRankPoints: UInt32
    public let nextRankPoints: UInt32
    public let entry: AchievementEntry
    public init(from decoder: BinaryDecoder) throws {
        _ = try decoder.decode(UInt16.self)
        points = try decoder.decode(UInt32.self); rank = try decoder.decode(UInt16.self)
        currentRankPoints = try decoder.decode(UInt32.self); nextRankPoints = try decoder.decode(UInt32.self)
        entry = try decoder.decode(AchievementEntry.self)
    }
}
