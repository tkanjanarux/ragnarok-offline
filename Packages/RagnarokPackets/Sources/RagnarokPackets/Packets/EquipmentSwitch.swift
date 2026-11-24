import BinaryIO

/// rAthena PACKETVER 20211103: 0a98/0a9a use a 16-bit result (not 2017's 32-bit field).
public struct EquipmentSwitchResult: DecodablePacket {
    public static let size = 10
    public let type: UInt16
    public let index: UInt16
    public let position: UInt32
    public let result: UInt16
    public init(from decoder: BinaryDecoder) throws {
        type = try decoder.decode(UInt16.self); index = try decoder.decode(UInt16.self)
        position = try decoder.decode(UInt32.self); result = try decoder.decode(UInt16.self)
    }
}
public struct EquipmentSwitchComplete: DecodablePacket {
    public static let size = 4
    public let result: UInt16
    public init(from decoder: BinaryDecoder) throws {
        _ = try decoder.decode(UInt16.self); result = try decoder.decode(UInt16.self)
    }
}
public enum EquipmentSwitchRequest: EncodablePacket {
    case add(index: UInt16, position: UInt32), remove(index: UInt16), swap
    public func encode(to encoder: BinaryEncoder) throws {
        switch self {
        case .add(let index, let position):
            try encoder.encode(UInt16(0xa97)); try encoder.encode(index); try encoder.encode(position)
        case .remove(let index):
            try encoder.encode(UInt16(0xa99)); try encoder.encode(index)
        case .swap: try encoder.encode(UInt16(0xa9c))
        }
    }
}
