import Foundation
import RagnarokPackets

struct BankState {
    enum Operation { case opening, deposit, withdraw }
    struct Pending { let token = UUID(); let operation: Operation }
    var visible = false
    var authorized = false
    var balance: Int64?
    var pending: Pending?
    var message: String?
    mutating func receive(operation: Operation, reason: Int16, money: Int64) {
        guard pending?.operation == operation, money >= 0 else { return }
        balance = money; pending = nil
        message = reason == 0 ? "Transaction completed." : "The server rejected this transaction (\(reason))."
    }
}

extension PlaySession {
    func openBank() {
        guard enchant.pending == nil, !buyingStore.busy, !vending.active, vending.purchase == nil, !rodex.busy, !trade.active, trade.waiting == nil else { return }
        bank.visible = true
        guard bank.pending == nil else { return }
        bank.authorized = false; bank.balance = nil
        bank.pending = .init(operation: .opening); bank.message = "Contacting the bank…"
        var p = PACKET_CZ_REQ_OPEN_BANKING(); p.packetType = HEADER_CZ_REQ_OPEN_BANKING; p.AID = partyAccountID
        sendFoundationPacket(p); waitForBank()
    }
    func bankOpened() {
        guard bank.pending?.operation == .opening else { return }
        bank.authorized = true
        var p = PACKET_CZ_REQ_BANKING_CHECK(); p.packetType = HEADER_CZ_REQ_BANKING_CHECK; p.AID = partyAccountID
        sendFoundationPacket(p)
    }
    func bankChecked(_ p: PACKET_ZC_BANKING_CHECK) {
        guard bank.authorized, bank.pending?.operation == .opening else { return }
        bank.pending = nil
        if p.reason == 0 && p.money >= 0 { bank.balance = p.money; bank.message = nil }
        else { bank.authorized = false; bank.message = "Bank balance unavailable." }
    }
    func transferBank(amount: Int32, deposit: Bool) {
        guard !hasPendingInventoryOperation else { return }
        guard bank.authorized, bank.pending == nil, let balance = bank.balance, amount > 0,
              cart.pending == nil, refine.pending == nil, itemSelection.pending == nil,
              deposit ? Int(amount) <= playerStatus.zeny : Int64(amount) <= balance else { return }
        bank.pending = .init(operation: deposit ? .deposit : .withdraw); bank.message = "Waiting for the server…"
        if deposit {
            var p = PACKET_CZ_REQ_BANKING_DEPOSIT(); p.packetType = HEADER_CZ_REQ_BANKING_DEPOSIT
            p.AID = partyAccountID; p.zeny = amount; sendFoundationPacket(p)
        } else {
            var p = PACKET_CZ_REQ_BANKING_WITHDRAW(); p.packetType = HEADER_CZ_REQ_BANKING_WITHDRAW
            p.AID = partyAccountID; p.zeny = amount; sendFoundationPacket(p)
        }
        waitForBank()
    }
    func waitForBank() {
        guard let token = bank.pending?.token else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.bank.pending?.token == token else { return }
            self.bank.message = "No server response. Reconnect before trying again."
            // Retain the lock: a delayed acknowledgement must never cause a second transfer.
        }
    }
    func closeBank() {
        bank.visible = false; bank.authorized = false
        var p = PACKET_CZ_REQ_CLOSE_BANKING(); p.packetType = HEADER_CZ_REQ_CLOSE_BANKING; p.AID = partyAccountID
        sendFoundationPacket(p)
    }
}
