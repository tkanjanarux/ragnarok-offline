import BinaryIO

/// Two-byte requests used by the 2021 cash shop protocol.
public struct CashShopRequest: EncodablePacket {
    public enum Action: Int16, Sendable {
        case list = 0x8c9
        case close = 0x84a
    }
    public let action: Action
    public init(_ action: Action) { self.action = action }
    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(action.rawValue)
    }
}
