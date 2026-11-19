import BinaryIO

/// rAthena clif_party_leaderchanged, fixed 10-byte packet 0x07fc.
public struct PartyLeaderChanged: DecodablePacket {
    public static var size: Int { 10 }
    public let previousLeader: UInt32
    public let newLeader: UInt32
    public init(from decoder: BinaryDecoder) throws {
        _ = try decoder.decode(Int16.self)
        previousLeader = try decoder.decode(UInt32.self)
        newLeader = try decoder.decode(UInt32.self)
    }
}
