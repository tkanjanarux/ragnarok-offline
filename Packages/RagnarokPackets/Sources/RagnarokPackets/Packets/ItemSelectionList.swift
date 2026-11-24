import BinaryIO

/// 0177/017b: server-authorized inventory indices, not item IDs.
/// PACKETVER 20211103; reject malformed row lengths before reading indices.
public struct ItemSelectionList: DecodablePacket {
    public static let size = -1
    public let type: Int16
    public let indices: [UInt16]
    public init(from decoder: BinaryDecoder) throws {
        type = try decoder.decode(Int16.self)
        let length = Int(try decoder.decode(UInt16.self))
        guard [Int16(0x177), 0x17b].contains(type), length >= 4,
              length <= 65534, (length - 4) % 2 == 0 else {
            throw PacketDecodingError.invalidPacketLength(type, length)
        }
        indices = try decoder.decode([UInt16].self, count: (length - 4) / 2)
    }
}
