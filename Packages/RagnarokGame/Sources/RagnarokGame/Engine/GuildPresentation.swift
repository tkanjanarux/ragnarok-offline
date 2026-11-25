import Foundation

/// Presentation rules shared by the guild window and portable regression tests.
/// Never supplies substitute server values or changes the authoritative roster.
enum GuildPresentation {
    static func validText(_ text: String, bytes: Int, required: Bool = false) -> Bool {
        (!required || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && text.utf8.count <= bytes && !text.contains("\0")
    }

    static func orderedMembers(_ state: GuildState) -> [GuildState.Member] {
        state.members.enumerated().sorted {
            let lhs = $0.element.data.currentState != 0, rhs = $1.element.data.currentState != 0
            return lhs == rhs ? $0.offset < $1.offset : lhs
        }.map(\.element)
    }

    static func member(_ id: String?, in state: GuildState) -> GuildState.Member? {
        guard let id else { return nil }
        return state.members.first { $0.id == id }
    }

    static func canExpel(_ id: String?, in state: GuildState, ownCharacter: UInt32) -> Bool {
        guard state.pending == nil, state.canExpel, let row = member(id, in: state) else { return false }
        return row.data.GID != ownCharacter && row.data.positionID != 0
    }

    static func canAssign(_ id: String?, position: Int32, in state: GuildState, ownCharacter: UInt32) -> Bool {
        guard state.id != nil, state.master, state.pending == nil,
              let row = member(id, in: state), row.data.GID != ownCharacter,
              state.positionNames[position] != nil else { return false }
        return row.data.positionID != position
    }

    static func sameContext(_ origin: UInt32?, state: GuildState) -> Bool {
        origin == state.id && state.pending == nil
    }
}
