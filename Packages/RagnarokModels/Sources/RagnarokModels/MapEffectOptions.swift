import RagnarokConstants

/// The map protocol combines multiple e_option bits in one field.
public struct MapEffectOptions: Sendable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public func contains(_ option: StatusChangeOption) -> Bool {
        (rawValue & option.rawValue) != 0
    }
}
