import Foundation

struct ItemSelectionState {
    enum Kind: Equatable { case identify, card, arrow }
    struct Selection {
        var kind: Kind
        var values: [Int]
    }
    struct Pending {
        var token = UUID()
        var kind: Kind
        var index: Int
        var itemID: Int
        var cardIndex: Int?
        var cardID: Int?
    }
    var selection: Selection?
    var pending: Pending?
    var requestedCard: (index: Int, itemID: Int)?
    var message: String?
    var visible = false
    var timedOut = false

    mutating func show(_ kind: Kind, values: [Int]) {
        guard pending == nil else { return }
        selection = .init(kind: kind, values: Array(Set(values)).sorted())
        message = values.isEmpty ? "No eligible items." : nil
        visible = true; timedOut = false
    }

    mutating func expire(token: UUID) {
        guard pending?.token == token else { return }
        // Never retry an ambiguous item mutation. Retain correlation for a late ACK.
        timedOut = true
        message = "No server reply yet. Close this window and reconnect before trying again."
    }
}
