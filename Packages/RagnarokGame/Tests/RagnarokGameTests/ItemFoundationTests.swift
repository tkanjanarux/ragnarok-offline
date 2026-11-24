import BinaryIO
import Foundation
import RagnarokModels
import RagnarokPackets
import Testing
@testable import RagnarokGame

struct ItemFoundationTests {
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
