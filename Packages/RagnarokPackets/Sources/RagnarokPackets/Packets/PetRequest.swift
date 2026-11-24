import BinaryIO
public enum PetRequest: EncodablePacket {
    case evolve(UInt32), command(UInt8), hatch(UInt16), capture(UInt32), rename(String), autoFeed(Bool)
    public func encode(to encoder: BinaryEncoder) throws {
        switch self {
        case .evolve(let egg): try encoder.encode(UInt16(0x9fb)); try encoder.encode(UInt16(8)); try encoder.encode(egg)
        case .command(let command): try encoder.encode(UInt16(0x1a1)); try encoder.encode(command)
        case .hatch(let index): try encoder.encode(UInt16(0x1a7)); try encoder.encode(index)
        case .capture(let id): try encoder.encode(UInt16(0x19f)); try encoder.encode(id)
        case .rename(let name):
            guard !name.isEmpty, name.utf8.count <= 23, !name.contains("\0") else { throw SocialPacketError.invalidText }
            try encoder.encode(UInt16(0x1a5)); try encoder.encode(name, lengthOfBytes: 24, encoding: .utf8)
        case .autoFeed(let enabled): try encoder.encode(UInt16(0x2d8)); try encoder.encode(UInt32(2)); try encoder.encode(UInt32(enabled ? 1 : 0))
        }
    }
}

public struct PetEvolutionResult: DecodablePacket {
    public static let size = 6
    public let result: UInt32
    public init(from d: BinaryDecoder) throws { _ = try d.decode(UInt16.self); result = try d.decode(UInt32.self) }
}
