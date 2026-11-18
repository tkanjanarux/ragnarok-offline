import BinaryIO

/// Raw, bounded quest payloads for the server's 2015 quest protocol.
public struct QuestWirePacket: DecodablePacket {
    public static let size = -1
    public let type: Int16
    public let bytes: [UInt8]
    public init(type: Int16, bytes: [UInt8]) { self.type = type; self.bytes = bytes }
    public init(from decoder: BinaryDecoder) throws {
        throw PacketDecodingError.unknownPacket(0)
    }
}
