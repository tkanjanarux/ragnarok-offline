import Testing
import BinaryIO
import RagnarokModels
import RagnarokPackets
@testable import RagnarokGame

@Test func storageDepositPreservesEquipmentMetadataFromWire() throws {
    var add = PACKET_ZC_ADD_ITEM_TO_STORE()
    add.packetType = HEADER_ZC_ADD_ITEM_TO_STORE
    add.index = 1
    add.amount = 1
    add.itemId = 1202
    add.itemType = 4
    add.identified = 1
    add.damaged = 1
    add.refine = 7
    add.grade = 2
    add.slot.card = [4001, 0, 0, 0]
    var option = ItemOptions()
    option.index = 1
    option.value = 5
    add.option_data[0] = option
    var storage = Storage(name: "Storage")
    let bytes = try PacketEncoder().encode(add)
    storage.update(from: try PACKET_ZC_ADD_ITEM_TO_STORE(from: BinaryDecoder(data: bytes)))
    let item = try #require(storage.items[1])
    #expect(item.amount == 1)
    #expect(item.itemID == 1202)
    #expect(item.isIdentified)
    #expect(item.isDamaged)
    #expect(item.refineLevel == 7)
    #expect(item.enchantGrade == 2)
    #expect(item.slots == [4001, 0, 0, 0])
    #expect(item.hasRandomOptions == true)
    #expect(item.randomOptions == [.init(option)])
}

@Test func storageSecondTapWaitsForMatchingTerminalPacketOrClose() {
    var state = BasicInventoryTransactions()
    var item = InventoryItem()
    item.index = 2
    item.amount = 5
    let tooMany = state.beginStorage(.deposit, item: item, amount: 6)
    #expect(!tooMany)
    let deposit = state.beginStorage(.deposit, item: item, amount: 2)
    #expect(deposit)
    let duplicate = state.beginStorage(.deposit, item: item, amount: 2)
    #expect(!duplicate)
    state.receiveStorage(.withdraw, index: 2, amount: 2)
    state.receiveStorage(.deposit, index: 3, amount: 2)
    state.receiveStorage(.deposit, index: 2, amount: 1)
    #expect(state.busy)
    state.receiveStorage(.deposit, index: 2, amount: 2)
    #expect(!state.busy)
    let withdraw = state.beginStorage(.withdraw, item: item, amount: 3)
    #expect(withdraw)
    state.receiveStorage(.withdraw, index: 2, amount: 0)
    #expect(!state.busy)
    let pendingDeposit = state.beginStorage(.deposit, item: item, amount: 2)
    #expect(pendingDeposit)
    let close = state.beginStorageClose()
    #expect(close)
    let duplicateClose = state.beginStorageClose()
    #expect(!duplicateClose)
    let saleWhileClosing = state.beginShop(.sell)
    #expect(!saleWhileClosing)
    state.storageClosed()
    #expect(!state.busy)
}

@Test func saleWaitsForSellResultAndValidatesAmountsAndSlots() {
    var state = BasicInventoryTransactions()
    var inventory = Inventory()
    var item = InventoryItem()
    item.index = 2
    item.amount = 5
    inventory.append(item: item)
    let sale = NPCShopSale(index: 2, amount: 3)
    #expect(BasicInventoryTransactions.canSell([sale], offered: [2], inventory: inventory))
    #expect(!BasicInventoryTransactions.canSell([sale, sale], offered: [2], inventory: inventory))
    #expect(!BasicInventoryTransactions.canSell([sale], offered: [], inventory: inventory))
    #expect(!BasicInventoryTransactions.canSell([.init(index: 2, amount: 6)], offered: [2], inventory: inventory))
    let firstSale = state.beginShop(.sell)
    #expect(firstSale)
    let duplicateSale = state.beginShop(.sell)
    #expect(!duplicateSale)
    state.receiveShop(.buy)
    #expect(state.busy)
    state.receiveShop(.sell)
    #expect(!state.busy)
}

@Test func useItemAcknowledgementOnlyMutatesMatchingSuccessfulOwnerAndRemovesEmptySlot() {
    var inventory = Inventory()
    var item = InventoryItem()
    item.index = 2
    item.itemID = 611
    item.amount = 1
    inventory.append(item: item)
    var ack = PACKET_ZC_USE_ITEM_ACK()
    ack.index = 2
    ack.itemId = 611
    ack.AID = 10
    ack.result = 0
    inventory.update(from: ack, ownerID: 10)
    #expect(inventory.items[2]?.amount == 1)
    ack.result = 1
    inventory.update(from: ack, ownerID: 11)
    #expect(inventory.items[2]?.amount == 1)
    ack.itemId = 501
    inventory.update(from: ack, ownerID: 10)
    #expect(inventory.items[2]?.amount == 1)
    ack.itemId = 611
    inventory.update(from: ack, ownerID: 10)
    #expect(inventory.items[2] == nil)
}

@Test func magnifierCastsOnlyOnceForAnExplicitUseAndWaitsForServerList() throws {
    var state = ItemSelectionState()
    var skill = PACKET_ZC_AUTORUN_SKILL()
    skill.packetType = HEADER_ZC_AUTORUN_SKILL
    skill.skill_id = 40
    skill.skill_lv = 1
    let bytes = try PacketEncoder().encode(skill)
    let grant = try PACKET_ZC_AUTORUN_SKILL(from: BinaryDecoder(data: bytes))
    let unsolicited = state.acceptMagnifierSkill(grant)
    #expect(!unsolicited)

    let started = state.beginMagnifier(index: 4)
    let token = try #require(started)
    let duplicateUse = state.beginMagnifier(index: 4)
    #expect(duplicateUse == nil)
    let authorized = state.acceptMagnifierSkill(grant)
    let duplicateGrant = state.acceptMagnifierSkill(grant)
    #expect(authorized)
    #expect(!duplicateGrant)
    state.expireMagnifier(token: token)
    let retry = state.beginMagnifier(index: 4)
    #expect(retry == nil)

    state.show(.identify, values: [2])
    #expect(state.magnifier == nil)
    #expect(state.selection?.values == [2])
    #expect(state.visible)
}
