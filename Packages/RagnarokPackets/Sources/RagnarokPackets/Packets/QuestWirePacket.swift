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

/// CZ_ACTIVE_QUEST, PACKETVER 20211103. State is updated only upon ZC_ACTIVE_QUEST acknowledgment.
public struct QuestActiveRequest: EncodablePacket {
    public let questID: UInt32
    public let active: Bool
    public init(questID: UInt32, active: Bool) { self.questID = questID; self.active = active }
    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(Int16(0x02b6))
        try encoder.encode(questID)
        try encoder.encode(UInt8(active ? 1 : 0))
    }
}

public struct LeaveWaitingRoomRequest: EncodablePacket {
    public init() {}
    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(UInt16(0x00e3))
    }
}
