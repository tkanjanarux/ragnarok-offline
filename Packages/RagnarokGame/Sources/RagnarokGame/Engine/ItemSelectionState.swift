import Foundation
import RagnarokPackets

struct ItemSelectionState {
    var epoch = UUID()
    enum Kind: Equatable { case identify, card, arrow, produce, cooking, skill }
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
    static let magnifierItemID = 611
    static let identifySkillID: UInt16 = 40
    struct MagnifierRequest {
        let token = UUID()
        let index: Int
        var castSent = false
    }
    private(set) var magnifier: MagnifierRequest?

    mutating func beginMagnifier(index: Int) -> UUID? {
        guard magnifier == nil, pending == nil, selection == nil, requestedCard == nil else { return nil }
        let request = MagnifierRequest(index: index)
        magnifier = request
        return request.token
    }

    mutating func acceptMagnifierSkill(_ packet: PACKET_ZC_AUTORUN_SKILL) -> Bool {
        guard magnifier?.castSent == false, packet.skill_id == Self.identifySkillID,
              packet.skill_lv == 1 else { return false }
        magnifier?.castSent = true
        return true
    }

    mutating func receiveMagnifierUseResult(_ packet: PACKET_ZC_USE_ITEM_ACK, ownerID: UInt32) {
        guard packet.AID == ownerID, packet.itemId == Self.magnifierItemID,
              magnifier?.index == Int(packet.index), magnifier?.castSent == false, packet.result == 0 else { return }
        magnifier = nil
        message = "The server rejected the Magnifier."
        visible = true
    }

    mutating func expireMagnifier(token: UUID) {
        guard magnifier?.token == token else { return }
        // A cast may already have used the Magnifier. The next login reconciles it.
        message = "No Identify list returned. Reconnect before trying again."
        visible = true
    }

    var selection: Selection?
    var pending: Pending?
    var requestedCard: (index: Int, itemID: Int)?
    var message: String?
    var visible = false
    var timedOut = false
    var cookingType: UInt16 = 0
    var skillFlag: Int32 = 0
    var extraMaterials: [UInt32] = [0, 0, 0]

    mutating func show(_ kind: Kind, values: [Int]) {
        guard pending == nil else { return }
        if kind == .identify { magnifier = nil }
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
