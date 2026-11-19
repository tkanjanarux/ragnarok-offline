import BinaryIO

/// Normal Renewal party setup response: 0x07d8, 8 bytes.
public struct PartyOptions: DecodablePacket {
    public static var size: Int { 8 }
    public let exp: UInt32
    public let pickup: UInt8
    public let distribution: UInt8
    public init(from decoder: BinaryDecoder) throws {
        _ = try decoder.decode(Int16.self)
        exp = try decoder.decode(UInt32.self)
        pickup = try decoder.decode(UInt8.self)
        distribution = try decoder.decode(UInt8.self)
    }
}

public struct PartyOptionsRequest: EncodablePacket {
    public let exp: Bool
    public let pickup: Bool
    public let distribution: Bool
    public init(exp: Bool, pickup: Bool, distribution: Bool) {
        self.exp = exp; self.pickup = pickup; self.distribution = distribution
    }
    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(Int16(0x7d7))
        try encoder.encode(UInt32(exp ? 1 : 0))
        try encoder.encode(UInt8(pickup ? 1 : 0))
        try encoder.encode(UInt8(distribution ? 1 : 0))
    }
}
