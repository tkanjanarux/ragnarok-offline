import Foundation
import RagnarokPackets

struct RodexState {
    enum Operation: Equatable { case list, begin, check(String), read(UInt64), attach(Int), remove(Int), send, claim(UInt64, Bool), delete(UInt64) }
    var visible = false
    var writing = false
    var entries: [RodexList.Entry] = []
    var letter: RodexRead?
    var attachments: [Int: PACKET_ZC_ACK_ADD_ITEM_RODEX] = [:]
    var receiver: PACKET_ZC_CHECKNAME?
    var pending: Operation?
    var token: UUID?
    var message: String?
    var busy: Bool { writing || pending != nil }
    mutating func finish(_ operation: Operation, message: String? = nil) {
        guard pending == operation else { return }; pending = nil; token = nil; self.message = message
    }
    mutating func receive(_ list: RodexList) { entries = list.entries; finish(.list) }
    mutating func receive(_ read: RodexRead) {
        guard pending == .read(read.id) else { return }; letter = read; finish(.read(read.id))
    }
    mutating func claim(id: UInt64, items: Bool, result: Int8) {
        guard pending == .claim(id, items) else { return }
        if result == 0, letter?.id == id { if items { letter?.items = [] } else { letter?.zeny = 0 } }
        finish(.claim(id, items), message: result == 0 ? "Attachment received." : "The server rejected this claim (\(result)).")
    }
}

extension PlaySession {
    func openRodex() {
        guard !trade.active, trade.waiting == nil, bank.pending == nil, cart.pending == nil else { return }
        rodex.visible = true
        guard !rodex.busy else { return }
        waitForRodex(.list); sendFoundationPacket(RodexRequest.list)
    }
    func beginRodex() {
        guard !rodex.busy, !trade.active, bank.pending == nil, cart.pending == nil else { return }
        waitForRodex(.begin); sendFoundationPacket(RodexRequest.begin(""))
    }
    func closeRodex() {
        guard rodex.pending == nil else { rodex.visible = false; return }
        if rodex.writing { sendFoundationPacket(RodexRequest.cancel) }
        sendFoundationPacket(RodexRequest.close); rodex = RodexState()
    }
    func cancelRodex() {
        guard rodex.writing, rodex.pending == nil else { return }
        sendFoundationPacket(RodexRequest.cancel)
        rodex.writing = false; rodex.attachments = [:]; rodex.receiver = nil; rodex.message = nil
        // Draft attachments have not left inventory. No restoration is fabricated.
    }
    func checkRodexReceiver(_ name: String) {
        guard rodex.writing, rodex.pending == nil, !name.isEmpty, name.utf8.count < 24, !name.contains("\0") else { return }
        rodex.receiver = nil; waitForRodex(.check(name)); sendFoundationPacket(RodexRequest.check(name))
    }
    func readRodex(_ entry: RodexList.Entry) {
        guard !rodex.busy else { return }; rodex.letter = nil
        waitForRodex(.read(entry.id)); sendFoundationPacket(RodexRequest.read(entry.id, entry.tab))
    }
    func attachRodex(index: Int, amount: Int) {
        guard rodex.writing, rodex.pending == nil, rodex.attachments.count < 5 || rodex.attachments[index] != nil,
              let item = inventory.items[index], !item.isEquipped, amount > 0, amount <= Int(Int16.max),
              amount + Int(rodex.attachments[index]?.count ?? 0) <= item.amount, let wireIndex = UInt16(exactly: index) else { return }
        waitForRodex(.attach(index)); sendFoundationPacket(RodexRequest.attach(wireIndex, UInt16(amount)))
    }
    func removeRodex(index: Int) {
        guard rodex.writing, rodex.pending == nil, let item = rodex.attachments[index], item.count > 0 else { return }
        waitForRodex(.remove(index)); sendFoundationPacket(RodexRequest.remove(UInt16(index), UInt16(item.count)))
    }
    func sendRodex(receiver: String, title: String, text: String, zeny: String) {
        guard rodex.writing, rodex.pending == nil, let checked = rodex.receiver, checked.CharId > 0, checked.Name == receiver,
              !title.isEmpty, title.utf8.count < 40, text.utf8.count < 500, !title.contains("\0"), !text.contains("\0"),
              let amount = UInt64(zeny.isEmpty ? "0" : zeny), amount <= UInt64(max(0,playerStatus.zeny)), amount <= 2_000_000_000 else { return }
        waitForRodex(.send)
        sendFoundationPacket(RodexRequest.send(receiver: checked.Name, sender: character.name, character: checked.CharId, title: title, text: text, zeny: amount))
    }
    func claimRodex(items: Bool) {
        guard rodex.pending == nil, !rodex.writing, let letter = rodex.letter,
              items ? !letter.items.isEmpty : letter.zeny > 0 else { return }
        waitForRodex(.claim(letter.id, items)); sendFoundationPacket(RodexRequest.claim(letter.id, letter.tab, items))
    }
    func deleteRodex() {
        guard rodex.pending == nil, !rodex.writing, let letter = rodex.letter, letter.zeny == 0, letter.items.isEmpty else { return }
        waitForRodex(.delete(letter.id)); sendFoundationPacket(RodexRequest.delete(letter.id, letter.tab))
    }
    private func waitForRodex(_ operation: RodexState.Operation) {
        let token = UUID(); rodex.pending = operation; rodex.token = token; rodex.message = "Waiting for the server…"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, self.rodex.token == token else { return }
            self.rodex.message = "No server result. Reconnect before trying again."
        }
    }
}
