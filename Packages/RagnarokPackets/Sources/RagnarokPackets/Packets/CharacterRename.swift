import BinaryIO

/// PACKETVER20211103 uses direct CH_REQ_CHANGE_CHARNAME (0x08fc), not the
/// legacy 0x028d/0x028f handshake. The server validates and spends one credit.
public struct CharacterRenameRequest: EncodablePacket {
    public let characterID: UInt32
    public let name: String
    public init(characterID: UInt32, name: String) { self.characterID = characterID; self.name = name }
    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(UInt16(0x08fc))
        try encoder.encode(characterID)
        try encoder.encode(name, lengthOfBytes: 24, encoding: .utf8)
    }
}

public struct CharacterRenameResult: DecodablePacket {
    public static let size = 6
    public let result: UInt32
    public init(from decoder: BinaryDecoder) throws {
        let type = try decoder.decode(Int16.self)
        guard type == 0x08fd else { throw PacketDecodingError.packetMismatch(type) }
        result = try decoder.decode(UInt32.self)
    }
}
