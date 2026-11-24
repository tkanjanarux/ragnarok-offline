import BinaryIO
import Foundation
import RagnarokModels
import RagnarokPackets
import Testing
@testable import RagnarokGame

struct ItemFoundationTests {
    @Test func tradeReservationIsAppliedOnceAndCancelPickupRestores() throws {
        var inventory = Inventory()
        var item = InventoryItem(); item.index = 2; item.itemID = 501; item.amount = 10; item.isIdentified = true
        inventory.items[2] = item
        var trade = TradeState(); trade.active = true
        trade.pending = .init(index: 2, amount: 3, item: item)
        var ack = PACKET_ZC_ACK_ADD_EXCHANGE_ITEM(); ack.index = 2; ack.result = 1
        trade.receiveAdd(ack, inventory: &inventory)
        #expect(inventory.items[2]?.amount == 10 && trade.mine.isEmpty)
        trade.pending = .init(index: 2, amount: 3, item: item); ack.result = 0
        trade.receiveAdd(ack, inventory: &inventory)
        trade.receiveAdd(ack, inventory: &inventory)
        #expect(inventory.items[2]?.amount == 7 && trade.mine[2]?.amount == 3)
        var restore = PACKET_ZC_ITEM_PICKUP_ACK(); restore.Index = 2; restore.nameid = 501; restore.count = 3; restore.IsIdentified = 1
        inventory.update(from: restore); trade.finish("Cancelled")
        #expect(inventory.items[2]?.amount == 10 && !trade.active && trade.mine.isEmpty)
        #expect(try PacketEncoder().encode(TradeRequest.reply(true)) == Data([0xe6,0,3]))
        #expect(try PacketEncoder().encode(TradeRequest.commit) == Data([0xef,0]))
    }

    @Test func bankRejectAndLateReplyStayAuthoritative() throws {
        var bank = BankState()
        bank.balance = 100
        bank.pending = .init(operation: .deposit)
        let token = bank.pending?.token
        bank.receive(operation: .withdraw, reason: 0, money: 200)
        #expect(bank.pending?.token == token && bank.balance == 100)
        bank.receive(operation: .deposit, reason: 2, money: 100)
        #expect(bank.pending == nil && bank.balance == 100)
        bank.pending = .init(operation: .withdraw)
        bank.visible = false // closing the window does not discard a transaction result
        bank.receive(operation: .withdraw, reason: 0, money: 50)
        #expect(bank.balance == 50 && bank.pending == nil && !bank.visible)
        bank.receive(operation: .withdraw, reason: 0, money: 0)
        #expect(bank.balance == 50) // duplicate/unsolicited result cannot be applied twice
        var p = PACKET_CZ_REQ_BANKING_DEPOSIT()
        p.packetType = HEADER_CZ_REQ_BANKING_DEPOSIT; p.AID = 2100001; p.zeny = 12345
        #expect(try PacketEncoder().encode(p) == Data([0xa7,9,33,11,32,0,57,48,0,0]))
    }

    @Test func socialWireLengthsAndFriendIdentity() throws {
        let text = "สวัสดี"
        let bytes = try PacketEncoder().encode(ChannelChatRequest(channel: .whisper, text: text, recipient: "Tester"))
        #expect(bytes.count == 29 + text.utf8.count)
        #expect(bytes[0] == 0x96 && bytes.last == 0)
        #expect(throws: (any Error).self) { _ = try PacketEncoder().encode(ChannelChatRequest(channel: .whisper, text: "Hi", recipient: String(repeating: "a", count: 24))) }
        let reply = try PacketEncoder().encode(FriendRequest.reply(accountID: 42, characterID: 99, accept: true))
        #expect(reply == Data([8, 2, 42, 0, 0, 0, 99, 0, 0, 0, 1, 0, 0, 0]))
        var state = SocialState()
        var list = PACKET_ZC_FRIENDS_LIST()
        var a = PACKET_ZC_FRIENDS_LIST_sub(); a.AID = 42; a.CID = 99; a.name = "Same"
        var b = PACKET_ZC_FRIENDS_LIST_sub(); b.AID = 43; b.CID = 100; b.name = "Same"
        list.friends = [a,b]; state.receive(list)
        var status = PACKET_ZC_FRIENDS_STATE(); status.AID = 43; status.CID = 100; status.offline = 0
        state.receive(status)
        #expect(state.friends[0].online == false && state.friends[1].online == true)
        let removed = try FriendRemoved(from: BinaryDecoder(stream: MemoryStream(data: Data([10, 2, 42, 0, 0, 0, 99, 0, 0, 0]))))
        state.receive(removed)
        #expect(state.friends.count == 1 && state.friends[0].characterID == 100)
    }

    @Test func equipmentSwitchVersionAndRejection() throws {
        #expect(try PacketEncoder().encode(EquipmentSwitchRequest.remove(index: 2)) == Data([0x99, 0x0a, 2, 0]))
        #expect(try PacketEncoder().encode(EquipmentSwitchRequest.add(index: 2, position: 16)) == Data([0x97, 0x0a, 2, 0, 16, 0, 0, 0]))
        var state = EquipmentSwitchState()
        state.pending = .init(index: 2)
        let reject = try EquipmentSwitchResult(from: BinaryDecoder(stream: MemoryStream(data: Data([0x98, 0x0a, 2, 0, 16, 0, 0, 0, 2, 0]))))
        state.receive(reject)
        #expect(state.entries.isEmpty && state.pending == nil)
        let accepted = try EquipmentSwitchResult(from: BinaryDecoder(stream: MemoryStream(data: Data([0x98, 0x0a, 2, 0, 16, 0, 0, 0, 0, 0]))))
        state.receive(accepted)
        #expect(state.entries[2] == 16)
    }

    @Test func refineRequiresServerOpenedWindowAndMatchingItem() {
        var state = RefineState()
        var packet = PACKET_ZC_REFINING_MATERIAL_LIST()
        packet.itemIndex = 2; packet.blacksmithBlessing = 4
        var material = PACKET_ZC_REFINING_MATERIAL_LIST_SUB()
        material.itemId = 984; material.chance = 60; material.zeny = 10000
        packet.req = [material]
        state.receive(packet)
        #expect(state.materials.isEmpty)
        state.authorized = true; state.selectedIndex = 3
        state.receive(packet)
        #expect(state.materials.isEmpty)
        state.selectedIndex = 2; state.receive(packet)
        #expect(state.materials.first?.chance == 60 && state.blessingCount == 4)
        material.zeny = -1; packet.req = [material]; state.receive(packet)
        #expect(state.materials.isEmpty)
    }

    @Test func serverIndicesAndMalformedLists() throws {
        let stream = MemoryStream(data: Data([0x77, 1, 8, 0, 2, 0, 44, 1]))
        let list = try ItemSelectionList(from: BinaryDecoder(stream: stream))
        #expect(list.indices == [2, 300])
        for bytes: [UInt8] in [[0x77, 1, 5, 0, 2], [0x7b, 1, 2, 0]] {
            #expect(throws: (any Error).self) {
                _ = try ItemSelectionList(from: BinaryDecoder(stream: MemoryStream(data: Data(bytes))))
            }
        }
        var cancel = PACKET_CZ_REQ_ITEMIDENTIFY()
        cancel.packetType = HEADER_CZ_REQ_ITEMIDENTIFY; cancel.index = UInt16.max
        #expect(try PacketEncoder().encode(cancel) == Data([0x78, 1, 0xff, 0xff]))
        var card = PACKET_CZ_REQ_ITEMCOMPOSITION()
        card.packetType = HEADER_CZ_REQ_ITEMCOMPOSITION; card.index_card = 2; card.index_equip = 300
        #expect(try PacketEncoder().encode(card) == Data([0x7c, 1, 2, 0, 44, 1]))
    }

    @Test func itemFlagsAndPickupRemainAuthoritative() {
        var equip = EQUIPITEM_INFO()
        equip.index = 2; equip.ITID = 1101; equip.Flag = 3; equip.RefiningLevel = 7
        let item = InventoryItem(from: equip)
        #expect(item.isIdentified && item.isDamaged && item.refineLevel == 7)
        var inventory = Inventory()
        var pickup = PACKET_ZC_ITEM_PICKUP_ACK()
        pickup.Index = 2; pickup.nameid = 1101; pickup.count = 1; pickup.result = 1
        inventory.update(from: pickup)
        #expect(inventory.items.isEmpty)
        pickup.result = 0; pickup.IsIdentified = 1; pickup.refiningLevel = 9
        inventory.update(from: pickup)
        #expect(inventory.items[2]?.refineLevel == 9 && inventory.items[2]?.isIdentified == true)
    }

    @Test func cartTransferWaitsForBothSidesAndIgnoresUnrelatedEvents() {
        var cart = CartState()
        cart.pending = .init(toCart: true, index: 7, itemID: 501, amount: 3)
        cart.receiveTransferEvent(toCart: true, source: true, index: 8, itemID: 501, amount: 3)
        #expect(cart.pending?.receivedSource == false)
        var add = PACKET_ZC_ADD_ITEM_TO_CART()
        add.index = 2; add.itemId = 501; add.amount = 3; add.identified = 1
        cart.receiveAdded(add)
        #expect(cart.pending != nil && cart.inventory.items[2]?.amount == 3)
        cart.receiveTransferEvent(toCart: true, source: true, index: 7, itemID: 501, amount: 3)
        #expect(cart.pending == nil)
        cart.pending = .init(toCart: false, index: 2, itemID: 501, amount: 2)
        var remove = PACKET_ZC_DELETE_ITEM_FROM_CART()
        remove.index = 2; remove.amount = 2
        cart.receiveRemoved(remove)
        #expect(cart.inventory.items[2]?.amount == 1 && cart.pending != nil)
        cart.receiveTransferEvent(toCart: false, source: false, index: 9, itemID: 501, amount: 2)
        #expect(cart.pending == nil)
        #expect(cart.inventory.items[2]?.amount == 1) // no second local subtraction
    }

    @Test func timeoutDoesNotRetryOrReleaseAmbiguousMutation() {
        var state = ItemSelectionState()
        state.show(.identify, values: [2, 2, 3])
        #expect(state.selection?.values == [2, 3])
        state.pending = .init(kind: .identify, index: 2, itemID: 1101)
        let token = state.pending!.token
        state.expire(token: UUID())
        #expect(!state.timedOut)
        state.expire(token: token)
        #expect(state.timedOut && state.pending?.token == token)
        state.show(.card, values: [5])
        #expect(state.selection?.kind == .identify)
        state = ItemSelectionState() // map/disconnect resets session-scoped state
        state.expire(token: token)
        #expect(state.pending == nil && !state.visible)
    }
}
