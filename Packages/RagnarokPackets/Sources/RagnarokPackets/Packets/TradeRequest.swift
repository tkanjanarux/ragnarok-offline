import BinaryIO
public enum TradeRequest: EncodablePacket {
    case invite(UInt32), reply(Bool), lock, cancel, commit
    public func encode(to encoder: BinaryEncoder) throws {
        switch self {
        case .invite(let id): try encoder.encode(UInt16(0xe4)); try encoder.encode(id)
        case .reply(let accept): try encoder.encode(UInt16(0xe6)); try encoder.encode(UInt8(accept ? 3 : 4))
        case .lock: try encoder.encode(UInt16(0xeb))
        case .cancel: try encoder.encode(UInt16(0xed))
        case .commit: try encoder.encode(UInt16(0xef))
        }
    }
}
