import BinaryIO
import Foundation
import RagnarokModels
import RagnarokPackets
import Testing
@testable import RagnarokGame

struct ItemFoundationTests {
    @Test func followerManualCommandsUseOwnedActorAndPackedDestination() throws {
        var move = PACKET_CZ_REQUEST_MOVENPC(); move.packetType = 0x232; move.GID = 0x12345678; move.PosDir = [0xff, 0xff, 0xf0]
        #expect(try PacketEncoder().encode(move) == Data([0x32,2,0x78,0x56,0x34,0x12,0xff,0xff,0xf0]))
        #expect(try PacketEncoder().encode(FollowerRequest.attack(7, 12)) == Data([0x33,2,7,0,0,0,12,0,0,0,0]))
        #expect(try PacketEncoder().encode(FollowerRequest.follow(7)) == Data([0x34,2,7,0,0,0]))
    }

    @Test func enchantAuthoritativeSlotsAndResetPreserveCards() throws {
        let catalog = try #require(EnchantCatalog.shared)
        #expect(catalog.recipes.count == 138)
        var state = EnchantState(); state.group = 33
        var item = InventoryItem(); item.index = 2; item.itemID = 600028; item.isIdentified = true
        item.enchantGrade = 0; item.hasRandomOptions = false; item.slots = [4001, 0, 0, 0]
        var inventory = Inventory(); inventory.items[2] = item
        let first = try #require(state.actions(for: item, registered: false).first { $0.kind == .perfect && $0.item == 4818 })
        #expect(first.slot == 3 && first.price == 100000)
        #expect(state.actions(for: item, registered: true).isEmpty)
        state.pending = .init(index: 2, itemID: item.itemID, originalSlots: item.slots, cardSlots: 2, action: first)
        var response = PACKET_ZC_RESPONSE_ENCHANT(); response.msgId = 3857; response.ITID = 4818
        state.receive(response, inventory: &inventory)
        #expect(inventory.items[2]?.slots == [4001, 0, 0, 4818] && state.group == nil)
        state.receive(response, inventory: &inventory) // Duplicate acknowledgement is inert.
        state.group = 33; item = try #require(inventory.items[2])
        let reset = try #require(state.actions(for: item, registered: false).first { $0.kind == .reset })
        state.pending = .init(index: 2, itemID: item.itemID, originalSlots: item.slots, cardSlots: 2, action: reset)
        response.ITID = 0; state.receive(response, inventory: &inventory)
        #expect(inventory.items[2]?.slots == [4001, 0, 0, 0])
        state.group = 33; item.enchantGrade = nil
        #expect(state.actions(for: item, registered: false).isEmpty)
        var request = PACKET_CZ_REQUEST_PERFECT_ENCHANT(); request.packetType = 0xb9c; request.enchant_group = 33; request.index = 2; request.ITID = 4818
        #expect(try PacketEncoder().encode(request) == Data([0x9c,11,33,0,0,0,0,0,0,0,2,0,0xd2,0x12,0,0]))
    }
    @Test func enchantFailureOrReplacedInventoryDoesNotMutate() {
        var state = EnchantState(); var inventory = Inventory(); var item = InventoryItem(); item.index = 2; item.itemID = 600028
        inventory.items[2] = item
        let action = EnchantState.Action(kind: .perfect, slot: 3, item: 4818, price: 100000, materials: [])
        state.pending = .init(index: 2, itemID: 600028, originalSlots: item.slots, cardSlots: 2, action: action)
        var response = PACKET_ZC_RESPONSE_ENCHANT(); response.msgId = 3858
        state.receive(response, inventory: &inventory); #expect(inventory.items[2]?.slots == [0,0,0,0])
        state.pending = .init(index: 2, itemID: 600028, originalSlots: item.slots, cardSlots: 2, action: action)
        inventory.items[2]?.itemID = 1101; response.msgId = 3857; response.ITID = 4818
        state.receive(response, inventory: &inventory); #expect(inventory.items[2]?.slots == [0,0,0,0])
    }

    @Test func buyingStoreSaleDeletionIsAcknowledgedExactlyOnce() throws {
        var inventory = Inventory(); var item = InventoryItem(); item.index = 2; item.itemID = 909; item.amount = 10; inventory.items[2] = item
        let packet = try BuyingStoreSold(from: BinaryDecoder(stream: MemoryStream(data: Data([0x1c,8,2,0,2,0,100,0,0,0]))))
        var state = BuyingStoreState(); state.receive(packet,inventory: &inventory); #expect(inventory.items[2]?.amount == 10)
        state.sale = .init(index: 2,itemID: 909,amount: 2,price: 100)
        state.receive(packet,inventory: &inventory); #expect(inventory.items[2]?.amount == 8 && state.sale == nil)
        state.receive(packet,inventory: &inventory); #expect(inventory.items[2]?.amount == 8)
        #expect(try PacketEncoder().encode(BuyingStoreRequest.sell(owner: 7,store: 50,index: 2,item: 909,amount: 2)) == Data([0x19,8,20,0,7,0,0,0,50,0,0,0,2,0,0x8d,3,0,0,2,0]))
        #expect(try PacketEncoder().encode(PetRequest.evolve(9069)) == Data([0xfb,9,8,0,0x6d,0x23,0,0]))
    }

    @Test func vendingPurchaseNeedsMatchingServerItemsAndMoney() throws {
        var state = VendingState(); state.browsing = 7
        var list = PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC(); list.AID = 8; list.venderId = 50
        state.receive(list); #expect(state.shop == nil)
        list.AID = 7; state.receive(list); #expect(state.shop?.venderId == 50)
        state.purchase = .init(owner: 7,shop: 50,index: 2,itemID: 501,amount: 2,beforeZeny: 1000,cost: 200)
        state.waiting = UUID()
        state.checkPurchase(zeny: 800); #expect(state.purchase != nil)
        state.receivedItem(502,count: 2,zeny: 800); #expect(state.purchase?.received == 0)
        state.receivedItem(501,count: 2,zeny: 1000); #expect(state.purchase != nil)
        state.checkPurchase(zeny: 800); #expect(state.purchase == nil && state.waiting == nil && state.shop == nil)
        #expect(try PacketEncoder().encode(VendingRequest.buy(7,50,2,2)) == Data([1,8,16,0,7,0,0,0,50,0,0,0,2,0,2,0]))
        #expect(throws: PacketDecodingError.self) {
            try PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC(from: BinaryDecoder(stream: MemoryStream(data: Data([0x3d,11,13,0,0,0,0,0,0,0,0,0,0]))))
        }
        state.boards[7] = .init(id: 7,name: "Shop"); state.browsing = 7; state.shop = list
        state.vanished(7); #expect(state.boards.isEmpty && state.shop == nil)
    }

    @Test func rodexActualServerReadAndDuplicateClaim() throws {
        // Captured from the isolated synthetic mail 910001, PACKETVER 20211103.
        let bytes = Data(base64Encoded: "YwtpAACx4g0AAAAAABUAQQEAAAAAAAABS25vd24gYXR0YWNoZWQgaXRlbXMAAgD1AQAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")!
        let packet = try RodexRead(from: BinaryDecoder(stream: MemoryStream(data: bytes)))
        #expect(packet.id == 910001 && packet.zeny == 321 && packet.items.count == 1)
        #expect(packet.items[0].ITID == 501 && packet.items[0].count == 2)
        var state = RodexState(); state.receive(packet); #expect(state.letter == nil)
        state.pending = .read(910001); state.receive(packet)
        state.claim(id: 910001, items: false, result: 0); #expect(state.letter?.zeny == 321)
        state.pending = .claim(910001,false); state.claim(id: 910002, items: false, result: 0)
        #expect(state.letter?.zeny == 321)
        state.claim(id: 910001, items: false, result: 1); #expect(state.letter?.zeny == 321)
        state.pending = .claim(910001,false); state.claim(id: 910001, items: false, result: 0)
        #expect(state.letter?.zeny == 0 && state.pending == nil)
        var bad = bytes; bad[23] = 6
        #expect(throws: PacketDecodingError.self) { try RodexRead(from: BinaryDecoder(stream: MemoryStream(data: bad))) }
    }
    @Test func rodexListBoundsAndUTF8WireLengths() throws {
        let empty = try RodexList(from: BinaryDecoder(stream: MemoryStream(data: Data([0xc2,10,5,0,1]))))
        #expect(empty.entries.isEmpty)
        #expect(throws: PacketDecodingError.self) { try RodexList(from: BinaryDecoder(stream: MemoryStream(data: Data([0xc2,10,6,0,1,0])))) }
        let data = try PacketEncoder().encode(RodexRequest.send(receiver: "Fixture", sender: "Sender", character: 42, title: "ทดสอบ", text: "Hello", zeny: 123))
        #expect(Int(data[2]) + 256 * Int(data[3]) == data.count)
        #expect(Int(data[60]) == "ทดสอบ".utf8.count + 1 && data.last == 0)
    }

    @Test func guildUsesCharacterIdentityAndServerPermissions() throws {
        var state = GuildState()
        var joined = PACKET_ZC_UPDATE_GDID(); joined.guildId = 10; joined.mode = 1; joined.isMaster = 0
        state.receive(joined)
        #expect(state.canInvite && !state.canExpel && !state.master)
        var a = GUILD_MEMBER_INFO(); a.AID = 1; a.GID = 2; a.char_name = "Same"
        var b = a; b.GID = 3
        var list = PACKET_ZC_MEMBERMGR_INFO(); list.guildMemberInfo = [a,b]; state.receive(list)
        #expect(state.members[0].id != state.members[1].id)
        state.remove(characterID: 2, ownID: 3)
        #expect(state.members.count == 1 && state.id == 10)
        state.remove(characterID: 3, ownID: 3)
        #expect(state.id == nil && !state.canInvite && state.members.isEmpty)
        let packet = try PacketEncoder().encode(GuildRequest.memberPosition(1,3,2))
        #expect(packet == Data([0x55,1,16,0,1,0,0,0,3,0,0,0,2,0,0,0]))
        #expect(throws: SocialPacketError.self) { try PacketEncoder().encode(GuildRequest.invite(String(repeating: "x", count: 24))) }
    }

    @Test func petAndHomunculusUpdatesKeepOwnerIdentity() throws {
        var pets = PetState(); var info = PACKET_ZC_PROPERTY_PET(); info.szName = "Poring"; info.nFullness = 50
        pets.receive(info)
        var change = PACKET_ZC_CHANGESTATE_PET(); change.GID = 42; change.type = 0; pets.receive(change)
        change.type = 2; change.GID = 99; change.data = 10; pets.receive(change)
        #expect(pets.info?.nFullness == 50)
        change.GID = 42; pets.receive(change); #expect(pets.info?.nFullness == 10)
        pets.vanished(99); #expect(pets.info != nil)
        pets.vanished(42); #expect(pets.info == nil && pets.actorID == nil)
        var followers = FollowerState(); var hom = PACKET_ZC_PROPERTY_HOMUN(); hom.hp = 100; hom.maxHp = 120
        followers.receive(hom)
        var state = PACKET_ZC_CHANGESTATE_MER(); state.gid = 7; state.state = 0; followers.receive(state)
        var parameter = PACKET_ZC_HO_PAR_CHANGE(); parameter.type = 5; parameter.value = 40; followers.homParameter(parameter)
        #expect(followers.homunculus?.hp == 40)
        followers.vanished(8); #expect(followers.homunculus != nil)
        followers.vanished(7); #expect(followers.homunculus == nil && followers.homSkills.isEmpty)
        #expect(try PacketEncoder().encode(FollowerRequest.homunculus(1)) == Data([0x2d,2,0,0,1]))
        #expect(try PacketEncoder().encode(PetRequest.autoFeed(true)) == Data([0xd8,2,2,0,0,0,1,0,0,0]))
    }

    @Test func mercenaryWireLayoutAndMalformedSkillList() throws {
        var data = Data([0x9b,2,42,0,0,0]); data.append(Data(repeating: 0, count: 16))
        data.append(Data("Mercenary".utf8)); data.append(Data(repeating: 0, count: 15))
        data.append(contentsOf: [10,0,100,0,0,0,120,0,0,0,20,0,0,0,30,0,0,0])
        data.append(Data(repeating: 0, count: 16))
        #expect(data.count == 80)
        let merc = try MercenaryInfo(from: BinaryDecoder(stream: MemoryStream(data: data)))
        #expect(merc.id == 42 && merc.name == "Mercenary" && merc.hp == 100 && merc.maxHP == 120)
        #expect(throws: PacketDecodingError.self) {
            try MercenarySkills(from: BinaryDecoder(stream: MemoryStream(data: Data([0x9d,2,5,0,0]))))
        }
    }

    @Test func achievementRowsAndClaimUseServerAuthority() throws {
        var data = Data([0x23,0x0a,72,0,1,0,0,0,10,0,0,0,1,0,5,0,0,0,20,0,0,0])
        data.append(contentsOf: [0xc1,0xd4,1,0,1]) // 120001, complete
        data.append(Data(repeating: 0, count: 40)); data.append(contentsOf: [1,0,0,0,0])
        let packet = try PACKET_ZC_ALL_ACH_LIST(from: BinaryDecoder(stream: MemoryStream(data: data)))
        var state = RewardState(); state.receive(packet)
        #expect(state.entries[120001]?.completed == true && state.entries[120001]?.rewarded == false)
        let result = try AchievementRewardResult(from: BinaryDecoder(stream: MemoryStream(data: Data([0x26,0x0a,0,0xc1,0xd4,1,0]))))
        state.receive(result); #expect(state.entries[120001]?.rewarded == false)
        state.pendingID = 120001; state.receive(result)
        #expect(state.entries[120001]?.rewarded == true && state.pendingID == nil)
        data[4] = 2
        #expect(throws: PacketDecodingError.self) {
            try PACKET_ZC_ALL_ACH_LIST(from: BinaryDecoder(stream: MemoryStream(data: data)))
        }
        #expect(try PacketEncoder().encode(RewardRequest.openAttendance) == Data([0x68,0x0a,5]))
    }

    @Test func chatRoomsExcludeNPCAndRequireMatchingJoin() throws {
        var state = ChatRoomState()
        var entry = PACKET_ZC_ROOM_NEWENTRY(); entry.id = 10; entry.owner = 20; entry.type = 2; entry.title = "Waiting Room"
        state.receive(entry); #expect(state.rooms.isEmpty)
        entry.type = 0; entry.title = "Players"; state.receive(entry)
        #expect(state.rooms[10]?.isPrivate == true)
        var joined = PACKET_ZC_ENTER_ROOM(); joined.chatId = 10
        var member = PACKET_ZC_ENTER_ROOM_sub(); member.name = "Owner"; member.flag = 0; joined.members = [member]
        state.receive(joined); #expect(!state.active)
        state.joiningID = 10; state.receive(joined)
        #expect(state.active && state.members["Owner"] == true)
        state.leave(); #expect(!state.active && state.members.isEmpty)
        let packet = try PacketEncoder().encode(ChatRoomRequest.configure(title: "RO", limit: 10, password: "", editing: false))
        #expect(packet.count == 17 && packet.prefix(4) == Data([0xd5,0,17,0]))
        #expect(throws: SocialPacketError.self) {
            try PacketEncoder().encode(ChatRoomRequest.configure(title: String(repeating: "x", count: 61), limit: 10, password: "", editing: false))
        }
    }

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
