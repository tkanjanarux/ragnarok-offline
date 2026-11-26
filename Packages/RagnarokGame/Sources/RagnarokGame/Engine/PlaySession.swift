//
//  PlaySession.swift
//  RagnarokGame
//
//  Created by Leon Li on 2026/10/28.
//

import Foundation
import Metal
import Observation
import RagnarokConstants
import RagnarokModels
import RagnarokNetwork
import RagnarokPackets

@MainActor
protocol PlaySessionDelegate: AnyObject {
    func playSession(_ playSession: PlaySession, didFailToEnterWithErrorMessage errorMessage: String)
    func playSessionDidRestart(_ playSession: PlaySession)
    func playSession(_ playSession: PlaySession, didReceiveErrorMessage errorMessage: String)
    func playSessionDidDisconnect(_ playSession: PlaySession)
}

@MainActor
@Observable
final class PlaySession {
    enum MapPhase {
        case connecting
        case loading(_ progress: Progress)
        case loaded(_ runtime: MapSceneRuntime)
    }

    private(set) var mapPhase: MapPhase = .connecting

    private(set) var account: AccountInfo
    private(set) var character: CharacterInfo

    var playerStatus: CharacterStatus
    var inventory: Inventory
    var skillList: SkillList
    var skillCooldowns: [Int : SkillCooldown]
    var statusChanges: [StatusChange]
    var shortcutList: ShortcutList
    let messageCenter: MessageCenter

    var quests: [UInt32: QuestEntry] = [:]
    var questUI = QuestUIState()
    enum ExamQueueState { case idle, joining, queued, leaving, refused }
    private(set) var examQueueState: ExamQueueState = .idle
    private(set) var examAdmissions = 0
    private var examRoomID: UInt32?
    var canAccessExamRoom: Bool {
        examRoomID != nil && quests[4011] != nil && mapScene?.mapName == "job_hunte.rsw"
    }
    var companions = CompanionState()
    @ObservationIgnored private var companionTimeout: Task<Void, Never>?
    var party = PartyState()
    let navigation = NavigationState()
    var itemSelection = ItemSelectionState()
    var cart = CartState()
    var hasPendingInventoryOperation: Bool {
        enchant.pending != nil || bank.pending != nil || cart.pending != nil || refine.pending != nil
            || itemSelection.pending != nil || equipmentSwitch.pending != nil || trade.pending != nil
            || trade.waiting != nil || rodex.pending != nil || vending.waiting != nil || buyingStore.waiting != nil
    }
    var enchant = EnchantState()
    var refine = RefineState()
    var equipmentSwitch = EquipmentSwitchState()
    var buyingStore = BuyingStoreState()
    var vending = VendingState()
    var rodex = RodexState()
    var guild = GuildState()
    var followers = FollowerState()
    var pets = PetState()
    var rewards = RewardState()
    var chatRoom = ChatRoomState()
    var trade = TradeState()
    var bank = BankState()
    var social = SocialState()
    @ObservationIgnored private var partyOptionsTimeout: Task<Void, Never>?
    var cashShop = CashShopState()
    @ObservationIgnored private var cashShopTimeout: Task<Void, Never>?

    var dialog: NPCDialog?
    var dealSelectionNPCID: UInt32?
    var npcShop: NPCShop?
    var storage: Storage?
    var warpList: WarpList?

    var interactionMode: GameInteractionMode = .direct

    @ObservationIgnored weak var delegate: (any PlaySessionDelegate)?

    @ObservationIgnored private let context: GameContext
    @ObservationIgnored private let audioPlayer: GameAudioPlayer

    @ObservationIgnored private var mapClient: NetworkClient?
    @ObservationIgnored private var keepaliveTask: Task<Void, Never>?

    @ObservationIgnored private var serverClock = ServerClock()
    @ObservationIgnored private var serverTimeRequestTime: ContinuousClock.Instant?

    var mapRuntime: MapSceneRuntime? {
        if case .loaded(let runtime) = mapPhase {
            runtime
        } else {
            nil
        }
    }

    var mapScene: MapScene? {
        mapRuntime?.scene
    }

    init(context: GameContext, audioPlayer: GameAudioPlayer, account: AccountInfo, character: CharacterInfo) {
        self.context = context
        self.audioPlayer = audioPlayer
        self.account = account
        self.character = character

        self.playerStatus = CharacterStatus(from: character)
        self.inventory = Inventory()
        self.skillList = SkillList()
        self.skillCooldowns = [:]
        self.statusChanges = []
        self.shortcutList = ShortcutList()
        self.messageCenter = MessageCenter(
            itemInfoTable: context.itemInfoTable,
            messageStringTable: context.messageStringTable
        )
        self.party.currentMap = PartyMember.mapKey(character.mapName)
    }

    /// Keeps the current cooldown when it would end later than the new one.
    func setSkillCooldown(_ cooldown: SkillCooldown) {
        if let current = skillCooldowns[cooldown.skillID], current.endTime >= cooldown.endTime {
            return
        }
        skillCooldowns[cooldown.skillID] = cooldown
    }

    /// Puts every skill in the shortcut list on cooldown, such as after a skill with a cast delay.
    func setGlobalSkillCooldown(startTime: ContinuousClock.Instant, duration: Duration) {
        for shortcut in shortcutList.rows.joined() {
            if case .skill(let skillID, _) = shortcut {
                let cooldown = SkillCooldown(skillID: skillID, startTime: startTime, duration: duration)
                setSkillCooldown(cooldown)
            }
        }
    }

    /// A status which is already active keeps its place in the list.
    func setStatusChange(_ statusChange: StatusChange) {
        if let index = statusChanges.firstIndex(where: { $0.statusID == statusChange.statusID }) {
            statusChanges[index] = statusChange
        } else {
            statusChanges.append(statusChange)
        }
    }

    func removeStatusChange(statusID: Int) {
        statusChanges.removeAll(where: { $0.statusID == statusID })
    }

    // MARK: - Map Client

    func start(mapServer: MapServerInfo) {
        let mapClient = NetworkClient(
            name: "Map",
            address: mapServer.ip,
            port: mapServer.port
        )
        self.mapClient = mapClient

        // Handle error stream
        Task { [weak self] in
            for await error in mapClient.errorStream {
                logger.warning("\(error)")
                self?.handleClientError(error, from: mapClient)
            }
        }

        // Handle packet stream
        Task { [weak self] in
            for await packet in mapClient.packetStream {
                guard let self, self.mapClient === mapClient else { continue }
                self.handlePacket(packet)
            }
        }

        mapClient.connect()

        let packet = PacketFactory.CZ_ENTER(account: account, charID: character.charID)
        mapClient.sendPacket(packet)

        if PACKET_VERSION < 20070521 {
            mapClient.receiveDataAndPacket(count: 4) { [weak self] data in
                let accountID = data.withUnsafeBytes({ $0.load(as: UInt32.self) })
                Task { @MainActor in
                    self?.account.update(accountID: accountID)
                }
            }
        } else {
            mapClient.receivePacket()
        }

        startKeepalive()
    }

    func stop() {
        followers = FollowerState()
        pets = PetState()
        buyingStore = BuyingStoreState()
        vending = VendingState()
        rodex = RodexState()
        guild = GuildState()
        rewards = RewardState()
        social = SocialState()
        equipmentSwitch = EquipmentSwitchState()
        chatRoom = ChatRoomState()
        trade = TradeState()
        bank = BankState()
        enchant = EnchantState()
        refine = RefineState()
        cart = CartState()
        itemSelection = ItemSelectionState()
        navigation.cancel()
        mapRuntime?.unload()

        keepaliveTask?.cancel()
        keepaliveTask = nil

        mapClient?.disconnect()
        mapClient = nil

        // The scene holds this session, so keeping the runtime would leak both.
        cashShopTimeout?.cancel()
        cashShop = CashShopState()
        partyOptionsTimeout?.cancel()
        companionTimeout?.cancel()
        companions = CompanionState()
        party = PartyState()
        examRoomID = nil
        examQueueState = .idle
        quests.removeAll()
        questUI = QuestUIState()
        mapPhase = .connecting
    }

    private func handleClientError(_ error: NetworkClientError, from client: NetworkClient) {
        guard client === mapClient else {
            return
        }

        switch error {
        case .network, .disconnected:
            navigation.cancel()
            followers = FollowerState()
            pets = PetState()
            buyingStore = BuyingStoreState()
            vending = VendingState()
            rodex = RodexState()
            guild = GuildState()
            rewards = RewardState()
            social = SocialState()
            equipmentSwitch = EquipmentSwitchState()
            chatRoom = ChatRoomState()
            trade = TradeState()
            bank = BankState()
            enchant = EnchantState()
            refine = RefineState()
            cart = CartState()
            itemSelection = ItemSelectionState()
            party = PartyState()
            if case .connecting = mapPhase {
                let localizedMessage = context.messageStringTable.localizedMessageString(forID: 1)
                delegate?.playSession(self, didFailToEnterWithErrorMessage: localizedMessage)
            } else {
                delegate?.playSessionDidDisconnect(self)
            }
        case .decoding, .encoding:
            break
        }
    }

    private func handlePacket(_ packet: any DecodablePacket) {
        party.receive(packet, ownID: account.accountID)
        switch packet {
        case let packet as PACKET_ZC_ACK_SCHEDULER_CASHITEM:
            cashShop.receive(packet)
        case let packet as PACKET_ZC_SE_CASHSHOP_OPEN:
            cashShop.receiveBalance(cashPoints: packet.cashPoints, kafraPoints: packet.kafraPoints, tab: packet.tab)
        case let packet as PACKET_ZC_SE_PC_BUY_CASHITEM_RESULT:
            if let next = cashShop.receivePurchaseResult(packet) {
                mapClient?.sendPacket(next)
                scheduleCashShopTimeout()
            } else if !cashShop.pending {
                cashShopTimeout?.cancel()
            }
        case let packet as PACKET_ZC_ACCEPT_ENTER:
            serverClock.synchronize(serverTick: packet.startTime, receiveTime: .now)
        case _ as PACKET_ZC_REFUSE_ENTER:
            let localizedMessage = context.messageStringTable.localizedMessageString(forID: 9)
            delegate?.playSession(self, didFailToEnterWithErrorMessage: localizedMessage)
        case let packet as PACKET_ZC_RESTART_ACK:
            if packet.type == 1 {
                delegate?.playSessionDidRestart(self)
            }
        case let packet as PACKET_ZC_ACK_REQ_DISCONNECT:
            messageCenter.addMessage(for: packet)
        case let packet as PACKET_ZC_AID:
            account.update(accountID: packet.accountID)
        case _ as PACKET_ZC_PING_LIVE:
            let packet = PacketFactory.CZ_PING_LIVE()
            mapClient?.sendPacket(packet)
        case let packet as PACKET_ZC_ROOM_NEWENTRY:
            chatRoom.receive(packet)
            if packet.type == 2, packet.title == "Waiting Room", packet.id > 0 {
                examRoomID = UInt32(packet.id)
            }
        case let packet as PACKET_ZC_DESTROY_ROOM:
            chatRoom.rooms.removeValue(forKey: packet.chatId)
            if packet.chatId == examRoomID {
                examRoomID = nil
                examQueueState = .idle
            }
        case let packet as PACKET_ZC_ENTER_ROOM:
            chatRoom.receive(packet)
            if examQueueState == .joining, packet.chatId == examRoomID {
                examQueueState = .queued
                examAdmissions += 1
            }
        case let packet as PACKET_ZC_REFUSE_ENTER_ROOM:
            if chatRoom.joiningID != nil { chatRoom.waiting = nil; chatRoom.joiningID = nil; chatRoom.message = "Cannot enter this room (\(packet.result))." }
            if examQueueState == .joining { examQueueState = .refused }
        case let packet as PACKET_ZC_MEMBER_EXIT:
            if chatRoom.active {
                chatRoom.members.removeValue(forKey: packet.name); chatRoom.waiting = nil
                if packet.name == character.name { chatRoom.leave(); chatRoom.message = packet.kicked == 0 ? "Left the room." : "Removed from the room." }
            }
            if packet.name == character.name { examQueueState = .idle }
        case let packet as PACKET_ZC_ACK_CREATE_CHATROOM:
            if let title = chatRoom.creatingTitle {
                chatRoom.creatingTitle = nil; chatRoom.waiting = nil
                if packet.flag == 0 { chatRoom.active = true; chatRoom.title = title; chatRoom.members = [character.name: true]; chatRoom.message = nil }
                else { chatRoom.message = "Cannot create this room (\(packet.flag))." }
            }
        case let packet as PACKET_ZC_MEMBER_NEWENTRY:
            if chatRoom.active { chatRoom.members[packet.name] = false }
        case let packet as PACKET_ZC_ROLE_CHANGE:
            if chatRoom.active { chatRoom.members[packet.name] = packet.flag == 0; chatRoom.waiting = nil; chatRoom.message = nil }
        case let packet as PACKET_ZC_CHANGE_CHATROOM:
            if chatRoom.active { chatRoom.title = packet.title; chatRoom.roomID = packet.chatId; chatRoom.waiting = nil; chatRoom.message = nil }
        case let packet as PACKET_ZC_NPCACK_MAPMOVE:
            examRoomID = nil
            examQueueState = .idle
            let mapName = packet.mapName.replacingOccurrences(of: ".gat", with: ".rsw")
            let position = SIMD2(x: Int(packet.xPos), y: Int(packet.yPos))

            navigation.mapChanging()
            if rodex.writing { sendFoundationPacket(RodexRequest.cancel) }
            buyingStore = BuyingStoreState()
            vending = VendingState()
            rodex = RodexState()
            guild.visible = false; guild.invitation = nil
            followers = FollowerState()
            pets = PetState()
            rewards.visible = false; rewards.attendanceVisible = false
            social.invitation = nil
            social.friendsVisible = false
            equipmentSwitch = EquipmentSwitchState()
            chatRoom = ChatRoomState()
            trade = TradeState()
            bank = BankState()
            enchant = EnchantState()
            refine = RefineState()
            cart = CartState()
            itemSelection = ItemSelectionState()

            if let mapScene, mapScene.mapName == mapName {
                mapScene.jump(toPosition: position)
                notifyMapLoaded()
                break
            }

            mapRuntime?.unload()

            let progress = Progress()
            mapPhase = .loading(progress)

            Task {
                guard let device = MTLCreateSystemDefaultDevice() else {
                    fatalError("PlaySession: Metal is not available on this device")
                }

                let world = try await context.resourceManager.world(mapName: mapName)
                let mapGrid = MapGrid(gat: world.gat)

                let scene = MapScene(
                    mapName: mapName,
                    mapGrid: mapGrid,
                    account: account,
                    character: character,
                    playerPosition: position,
                    resourceManager: context.resourceManager,
                    audioPlayer: audioPlayer,
                    playSession: self
                )
                let renderResources = MapSceneRenderResources(device: device)
                let runtime = MapSceneRuntime(
                    scene: scene,
                    world: world,
                    renderResources: renderResources
                )

                do {
                    try await runtime.load(progress: progress)

                    scene.player.effectState = MapEffectOptions(rawValue: character.effectState)
                    notifyMapLoaded()

                    mapPhase = .loaded(runtime)
                } catch {
                    logger.warning("Map scene failed to load: \(error)")
                }
            }
        case let packet as PACKET_ZC_NOTIFY_PLAYERMOVE:
            let moveData = MoveData(from: packet.moveData)
            mapScene?.onPlayerMoved(
                startTime: serverClock.time(forServerTick: packet.moveStartTime),
                startPosition: moveData.startPosition,
                endPosition: moveData.endPosition
            )
        case let packet as PACKET_ZC_STATUS:
            let basicStatus = CharacterBasicStatus(from: packet)
            playerStatus.update(from: basicStatus)
        case let packet as PACKET_ZC_SKILLINFO_LIST:
            skillList.replace(from: packet)
        case let packet as PACKET_ZC_SKILLINFO_UPDATE:
            if guild.skills[packet.skillId] != nil {
                guild.skills[packet.skillId]?.level = packet.level
                if guild.pendingSkill == packet.skillId { guild.pendingSkill = nil; guild.finish(.skill); sendFoundationPacket(GuildRequest.page(3)) }
            } else { skillList.update(from: packet) }
        case let packet as PACKET_ZC_SKILLINFO_UPDATE2:
            skillList.update(from: packet)
        case let packet as PACKET_ZC_ADD_SKILL:
            skillList.add(from: packet)
        case let packet as PACKET_ZC_SKILLINFO_DELETE:
            skillList.delete(from: packet)
        case let packet as PACKET_ZC_SKILL_POSTDELAY:
            let cooldown = SkillCooldown(from: packet, startTime: .now)
            setSkillCooldown(cooldown)
        case let packet as PACKET_ZC_USESKILL_ACK:
            if let skillID = SkillID(rawValue: Int(packet.skillId)),
               let element = Element(rawValue: Int(packet.element)) {
                mapScene?.onMapObjectSkillCast(skillID: skillID, sourceObjectID: packet.srcId, element: element, castTime: .milliseconds(packet.delayTime))
            }
        case let packet as PACKET_ZC_WARPLIST:
            warpList = WarpList(from: packet)
        case let packet as PACKET_ZC_AUTORUN_SKILL:
            var skill = SkillInfo()
            skill.skillID = Int(packet.skill_id)
            skill.flag = Int(packet.skill_type)
            skill.level = Int(packet.skill_lv)
            skill.spCost = Int(packet.skill_sp)
            skill.attackRange = Int(packet.skill_range)
            mapScene?.useSkill(skill, level: skill.level)
        case let packet as PACKET_ZC_DISPEL:
            mapScene?.onMapObjectSkillCastCancelled(sourceObjectID: packet.gid)
        case let packet as PACKET_ZC_ACK_TOUSESKILL:
            if packet.skillId == 1, packet.flag == 0, chatRoom.creatingTitle != nil {
                chatRoom.creatingTitle = nil; chatRoom.waiting = nil
                chatRoom.message = "Cannot create a room here. Check Basic Skill and move away from NPCs."
            }
            messageCenter.addMessage(for: packet)
        case let packet as PACKET_ZC_USE_SKILL:
            let objectSkill = MapObjectSkill(from: packet)
            mapScene?.onMapObjectSkillPerformed(objectSkill: objectSkill)
        case let packet as PACKET_ZC_NOTIFY_SKILL:
            let objectSkill = MapObjectSkill(from: packet)
            mapScene?.onMapObjectSkillPerformed(objectSkill: objectSkill)
            if packet.damage > 0 {
                let member = companions.profiles.first { $0.actor == packet.targetID }
                if packet.targetID == account.accountID || member != nil || party.members.contains(where: { $0.id == packet.targetID }) {
                    let skill = context.skillInfoTable.localizedSkillName(forSkillID: Int(packet.SKID))
                        ?? objectSkill.skillID?.stringValue ?? "Skill #\(packet.SKID)"
                    let target = mapScene?.objects[packet.targetID]?.name ?? member?.name ?? "#\(packet.targetID)"
                    let label = "\(skill) −\(packet.damage)"
                    messageCenter.messages.append(.init(content: "\(target) · \(label)", type: .info, category: .battle))
                    mapScene?.showSkillDamage(label, target: packet.targetID)
                }
            }
        case let packet as packet_skill_entry:
            mapScene?.updateGroundUnit(packet)
        case let packet as PACKET_ZC_SKILL_DISAPPEAR:
            mapScene?.removeGroundUnit(packet.GID)
        case let packet as PACKET_ZC_NOTIFY_GROUNDSKILL:
            if let skillID = SkillID(rawValue: Int(packet.SKID)) {
                let position = SIMD2(Int(packet.xPos), Int(packet.yPos))
                mapScene?.onGroundSkillCast(skillID: skillID, sourceObjectID: packet.AID, position: position)
            }
        case let packet as PACKET_ZC_SHORTCUT_KEY_LIST:
            shortcutList.update(from: packet)
        case let packet as PACKET_ZC_PAR_CHANGE:
            if let sp = StatusProperty(rawValue: Int(packet.varID)) {
                playerStatus.update(property: sp, value: Int(packet.count))
                vending.checkPurchase(zeny: playerStatus.zeny)
                mapScene?.onPlayerStatusChanged(property: sp, value: Int(packet.count))
            }
        case let packet as PACKET_ZC_LONGPAR_CHANGE:
            if let sp = StatusProperty(rawValue: Int(packet.varID)) {
                playerStatus.update(property: sp, value: Int(packet.amount))
                vending.checkPurchase(zeny: playerStatus.zeny)
            }
        case let packet as PACKET_ZC_LONGLONGPAR_CHANGE:
            if let sp = StatusProperty(rawValue: Int(packet.varID)) {
                playerStatus.update(property: sp, value: Int(packet.amount))
                vending.checkPurchase(zeny: playerStatus.zeny)
            }
        case let packet as PACKET_ZC_STATUS_CHANGE:
            if let sp = StatusProperty(rawValue: Int(packet.statusID)) {
                playerStatus.update(property: sp, value: Int(packet.value))
                vending.checkPurchase(zeny: playerStatus.zeny)
            }
        case let packet as PACKET_ZC_COUPLESTATUS:
            if let sp = StatusProperty(rawValue: Int(packet.statusType)) {
                playerStatus.update(property: sp, value: Int(packet.defaultStatus), value2: Int(packet.plusStatus))
            }
        case let packet as PACKET_ZC_ATTACK_RANGE:
            playerStatus.update(from: packet)
        case let packet as PACKET_ZC_ATTACK_FAILURE_FOR_DISTANCE:
            mapScene?.onPlayerTooFarToAttack(targetID: packet.targetAID)
        case let packet as PACKET_ZC_ACTION_FAILURE:
            messageCenter.addMessage(for: packet)
        case let packet as PACKET_ZC_RECOVERY:
            if let statusProperty = StatusProperty(rawValue: Int(packet.type)) {
                switch statusProperty {
                case .hp:
                    let amount = Int(packet.amount)
                    let hp = min(playerStatus.hp + amount, playerStatus.maxHp)
                    playerStatus.hp = hp
                    mapScene?.onPlayerHealthPointsRecovered(recovered: amount, current: hp)
                case .sp:
                    let amount = Int(packet.amount)
                    let sp = min(playerStatus.sp + amount, playerStatus.maxSp)
                    playerStatus.sp = sp
                    mapScene?.onPlayerSpellPointsRecovered(recovered: amount, current: sp)
                default:
                    break
                }
            }
        case let packet as PACKET_ZC_NOTIFY_EXP:
            messageCenter.addMessage(for: packet)
        case let packet as PACKET_ZC_INVENTORY_START:
            // invType: 0 = inventory, 1 = cart, 2 = storage, 3 = guild storage
            switch packet.invType {
            case 0:
                inventory = Inventory()
            case 1:
                cart.inventory = Inventory()
            case 2:
                storage = Storage(name: packet.name)
            default:
                break
            }
        case _ as PACKET_ZC_INVENTORY_END:
            break
        case let packet as packet_itemlist_normal:
            // invType: 0 = inventory, 1 = cart, 2 = storage, 3 = guild storage
            switch packet.invType {
            case 0:
                inventory.update(from: packet)
            case 1:
                cart.inventory.update(from: packet)
            case 2:
                storage?.update(from: packet)
            default:
                break
            }
        case let packet as packet_itemlist_equip:
            // invType: 0 = inventory, 1 = cart, 2 = storage, 3 = guild storage
            switch packet.invType {
            case 0:
                inventory.update(from: packet)
            case 1:
                cart.inventory.update(from: packet)
            case 2:
                storage?.update(from: packet)
            default:
                break
            }
        case let packet as PACKET_ZC_ITEM_ENTRY:
            let item = DroppedItem(from: packet)
            let position = SIMD2(x: Int(packet.x), y: Int(packet.y))
            mapScene?.onItemSpawned(item: item, position: position)
        case let packet as packet_dropflooritem:
            let item = DroppedItem(from: packet)
            let position = SIMD2(x: Int(packet.xPos), y: Int(packet.yPos))
            mapScene?.onItemSpawned(item: item, position: position)
        case let packet as PACKET_ZC_ITEM_DISAPPEAR:
            mapScene?.onItemVanished(objectID: packet.itemAid)
        case let packet as PACKET_ZC_ITEM_PICKUP_ACK:
            inventory.update(from: packet)
            if packet.result == 0 {
                vending.receivedItem(packet.nameid, count: UInt16(clamping: packet.count), zeny: playerStatus.zeny)
                cart.receiveTransferEvent(toCart: false, source: false, index: Int(packet.Index), itemID: Int(packet.nameid), amount: Int(packet.count))
            } else if cart.pending?.toCart == false {
                cart.pending = nil; cart.message = "The server rejected the inventory transfer."
            }
            messageCenter.addMessage(for: packet)
        case let packet as PACKET_ZC_USE_ITEM_ACK:
            inventory.update(from: packet)
            if packet.result != 0 {
                let effects: [UInt32: EffectID] = [501: .ef_potion1, 502: .ef_potion2,
                    503: .ef_potion3, 504: .ef_potion4, 505: .ef_potion5,
                    506: .ef_potion6, 569: .ef_potion1]
                if let effect = effects[packet.itemId] {
                    mapScene?.onEffectSpawned(effectID: effect, objectID: packet.AID)
                }
            }
        case let packet as QuestWirePacket:
            applyQuestPacket(packet)
        case let packet as ItemSelectionList:
            receiveItemSelection(packet)
        case let packet as PACKET_ZC_ACK_ITEMIDENTIFY:
            receiveIdentifyResult(packet)
        case let packet as PACKET_ZC_ACK_ITEMCOMPOSITION:
            receiveCompositionResult(packet)
        case let packet as PACKET_ZC_MAKINGARROW_LIST:
            itemSelection.show(.arrow, values: packet.items.map { Int($0.itemId) })
        case let packet as PACKET_ZC_MAKABLEITEMLIST:
            itemSelection.extraMaterials = [0, 0, 0]
            itemSelection.show(.produce, values: packet.items.map { Int($0.itemId) })
        case let packet as PACKET_ZC_MAKINGITEM_LIST:
            itemSelection.cookingType = packet.makeItem
            itemSelection.show(.cooking, values: packet.items.map { Int($0.itemId) })
        case let packet as PACKET_ZC_SKILL_SELECT_REQUEST:
            itemSelection.skillFlag = packet.flag
            itemSelection.show(.skill, values: packet.skillIds.map(Int.init))
        case let packet as PACKET_ZC_ACK_REQMAKINGITEM:
            if let pending = itemSelection.pending, [.produce, .cooking].contains(pending.kind), pending.itemID == Int(packet.itemId) {
                itemSelection.pending = nil; itemSelection.selection = nil
                itemSelection.message = packet.result == 0 || packet.result == 2 ? "Production succeeded." : "Production failed."
            }
        case _ as PACKET_ZC_OPEN_REFINING_UI:
            if refine.pending == nil { refine = RefineState() }
            refine.authorized = true; refine.visible = true
        case let packet as PACKET_ZC_REFINING_MATERIAL_LIST:
            refine.receive(packet)
        case let packet as PACKET_ZC_ACK_ITEMREFINING:
            receiveRefineResult(packet)
        case let packet as EquipmentSwitchResult:
            equipmentSwitch.receive(packet)
        case let packet as PACKET_ZC_SEND_SWAP_EQUIPITEM_INFO:
            equipmentSwitch.entries = Dictionary(packet.items.map { (Int($0.index), $0.position) }, uniquingKeysWith: { _, last in last })
        case let packet as EquipmentSwitchComplete:
            equipmentSwitch.pending = nil
            equipmentSwitch.message = packet.result == 0 ? "Equipment switched." : "The server rejected the equipment switch."

        case let packet as PACKET_ZC_REQ_WEAR_EQUIP_ACK:
            inventory.update(from: packet)
            if let item = inventory.items[Int(packet.index)] {
                messageCenter.addMessage(for: packet, itemID: item.itemID)
            }
        case let packet as PACKET_ZC_REQ_TAKEOFF_EQUIP_ACK:
            inventory.update(from: packet)
            if let item = inventory.items[Int(packet.index)] {
                messageCenter.addMessage(for: packet, itemID: item.itemID)
            }
        case let packet as PACKET_ZC_ITEM_THROW_ACK:
            inventory.update(from: packet)
        case let packet as PACKET_ZC_EQUIP_ARROW:
            inventory.update(from: packet)
        case let packet as PACKET_ZC_DELETE_ITEM_FROM_BODY:
            if packet.deleteType == 5 {
                cart.receiveTransferEvent(toCart: true, source: true, index: Int(packet.index), itemID: 0, amount: Int(packet.count))
            }
            inventory.update(from: packet)
        case let packet as packet_spawn_unit:
            let object = MapObject(from: packet)
            let posDir = PosDir(from: packet.PosDir)
            let direction = Direction(rawValue: posDir.direction) ?? .north
            let headDirection = HeadDirection(rawValue: Int(packet.headDir)) ?? .lookForward
            logger.info("Object \(object.objectID) spawned at \(posDir.position) direction: \(direction.rawValue)")
            mapScene?.onMapObjectSpawned(object: object, position: posDir.position, direction: direction, headDirection: headDirection)
        case let packet as packet_idle_unit:
            let object = MapObject(from: packet)
            let posDir = PosDir(from: packet.PosDir)
            let direction = Direction(rawValue: posDir.direction) ?? .north
            let headDirection = HeadDirection(rawValue: Int(packet.headDir)) ?? .lookForward
            logger.info("Object \(object.objectID) spawned at \(posDir.position) direction: \(direction.rawValue)")
            mapScene?.onMapObjectSpawned(object: object, position: posDir.position, direction: direction, headDirection: headDirection)
        case let packet as packet_unit_walking:
            let object = MapObject(from: packet)
            let moveData = MoveData(from: packet.MoveData)
            logger.info("Object \(object.objectID) moved from \(moveData.startPosition) to \(moveData.endPosition)")
            mapScene?.onMapObjectMoved(
                object: object,
                startTime: serverClock.time(forServerTick: packet.moveStartTime),
                startPosition: moveData.startPosition,
                endPosition: moveData.endPosition
            )
        case let packet as PACKET_ZC_STOPMOVE:
            let objectID = packet.AID
            let position = SIMD2(x: Int(packet.xPos), y: Int(packet.yPos))
            logger.info("Object \(objectID) stopped at \(position)")
            mapScene?.onMapObjectStopped(objectID: objectID, position: position)
        case let packet as PACKET_ZC_NOTIFY_VANISH:
            vending.vanished(packet.gid)
            buyingStore.vanished(packet.gid)
            followers.vanished(packet.gid)
            pets.vanished(packet.gid)
            chatRoom.rooms = chatRoom.rooms.filter { $0.value.owner != packet.gid }
            let objectID = packet.gid
            let type = UnitClearType(rawValue: Int(packet.type)) ?? .outsight
            logger.info("Object \(objectID) vanished (type: \(packet.type))")
            mapScene?.onMapObjectVanished(objectID: objectID, type: type)
        case let packet as PACKET_ZC_RESURRECTION:
            logger.info("Object \(packet.gid) resurrected")
            mapScene?.onMapObjectResurrected(objectID: packet.gid)
        case let packet as PACKET_ZC_CHANGE_DIRECTION:
            let direction = Direction(rawValue: Int(packet.dir)) ?? .north
            let headDirection = HeadDirection(rawValue: Int(packet.headDir)) ?? .lookForward
            mapScene?.onMapObjectDirectionChanged(objectID: packet.srcId, direction: direction, headDirection: headDirection)
        case let packet as PACKET_ZC_SPRITE_CHANGE:
            if packet.type == 0 { mapScene?.changeGroundUnitLook(packet.AID, kind: Int32(packet.val)) }
            if let look = Look(rawValue: Int(packet.type)) {
                mapScene?.onMapObjectSpriteChanged(objectID: packet.AID, look: look, value: Int(packet.val), value2: Int(packet.val2))
            }
        case let packet as PACKET_ZC_STATE_CHANGE:
            let bodyState = StatusChangeOption1(rawValue: Int(packet.bodyState)) ?? .none
            let healthState = StatusChangeOption2(rawValue: Int(packet.healthState)) ?? .none
            let effectState = MapEffectOptions(rawValue: Int(packet.effectState))
            if packet.AID == account.accountID { character.effectState = effectState.rawValue }
            mapScene?.onMapObjectStateChanged(objectID: packet.AID, bodyState: bodyState, healthState: healthState, effectState: effectState)
        case let packet as PACKET_ZC_NOTIFY_ACT:
            let objectAction = MapObjectAction(from: packet)
            mapScene?.onMapObjectActionPerformed(objectAction: objectAction)
            messageCenter.addMessage(for: objectAction, account: account)
        case let packet as PACKET_ZC_HP_INFO:
            mapScene?.onMapObjectHealthUpdated(objectID: packet.GID, hp: Int(packet.HP), maxHp: Int(packet.maxHP))
        case let packet as PACKET_ZC_MSG_STATE_CHANGE:
            if packet.AID == account.accountID {
                if packet.state != 0 {
                    let statusChange = StatusChange(statusID: Int(packet.index), startTime: .now, duration: nil)
                    setStatusChange(statusChange)
                } else {
                    removeStatusChange(statusID: Int(packet.index))
                }
            }
        case let packet as PACKET_ZC_MSG_STATE_CHANGE3:
            if packet.AID == account.accountID {
                switch OfficialStatusChangeID(rawValue: Int(packet.index)) {
                case .efst_postdelay, .efst_groundmagic:
                    if packet.remain > 0 {
                        setGlobalSkillCooldown(startTime: .now, duration: .milliseconds(packet.remain))
                    }
                default:
                    break
                }

                if packet.state != 0 {
                    let statusChange = StatusChange(from: packet, startTime: .now)
                    setStatusChange(statusChange)
                }
            }
        case let packet as PACKET_ZC_NOTIFY_EFFECT:
            if let effect = NotifyEffect(rawValue: Int(packet.effectId)) {
                mapScene?.onSpecialEffectSpawned(effect: effect, objectID: packet.aid)
            }
        case let packet as PACKET_ZC_NOTIFY_EFFECT2:
            if let effectID = EffectID(rawValue: Int(packet.effectID)) {
                mapScene?.onEffectSpawned(effectID: effectID, objectID: packet.AID)
            }
        case let packet as PACKET_ZC_SAY_DIALOG:
            if dialog?.npcID == packet.NpcID {
                dialog?.update(from: packet)
            } else {
                dialog = NPCDialog(from: packet)
            }
        case let packet as PACKET_ZC_WAIT_DIALOG:
            dialog?.update(from: packet)
        case let packet as PACKET_ZC_CLOSE_DIALOG:
            dialog?.update(from: packet)
        case let packet as PACKET_ZC_CLEAR_DIALOG:
            if dialog?.npcID == packet.GID {
                dialog = nil
            }
        case let packet as PACKET_ZC_MENU_LIST:
            dialog?.update(from: packet)
        case let packet as PACKET_ZC_OPEN_EDITDLG:
            dialog?.update(from: packet)
        case let packet as PACKET_ZC_OPEN_EDITDLGSTR:
            dialog?.update(from: packet)
        case _ as PACKET_ZC_SHOW_IMAGE:
            break
        case _ as PACKET_ZC_COMPASS:
            break
        case let packet as PACKET_ZC_SELECT_DEALTYPE:
            dealSelectionNPCID = packet.npcId
        case let packet as PACKET_ZC_PC_PURCHASE_ITEMLIST:
            npcShop = NPCShop(from: packet)
        case let packet as PACKET_ZC_PC_SELL_ITEMLIST:
            npcShop = NPCShop(from: packet)
        case let packet as PACKET_ZC_PC_PURCHASE_RESULT:
            if refine.pending != nil && packet.result != 0 {
                refine.pending = nil
                refine.message = "The server rejected the refining payment."
            }
            npcShop = nil
            messageCenter.addMessage(for: packet)
        case let packet as PACKET_ZC_PC_SELL_RESULT:
            npcShop = nil
            messageCenter.addMessage(for: packet)
        case let packet as PACKET_ZC_NOTIFY_STOREITEM_COUNTINFO:
            storage?.update(from: packet)
        case let packet as PACKET_ZC_ADD_ITEM_TO_STORE:
            storage?.update(from: packet)
        case let packet as PACKET_ZC_DELETE_ITEM_FROM_STORE:
            storage?.update(from: packet)
        case _ as PACKET_ZC_CLOSE_STORE:
            storage = nil
        case let packet as PACKET_ZC_NOTIFY_CHAT:
            mapScene?.showPublicChat(packet.Message, from: packet.GID)
            let message = ChatMessage(from: packet)
            messageCenter.add(message)
        case let packet as PACKET_ZC_WHISPER:
            social.lastWhisperSender = packet.sender
            let message = ChatMessage(from: packet)
            messageCenter.add(message)
        case let packet as PACKET_ZC_NOTIFY_PLAYERCHAT:
            if rodex.receiveCapability(packet.Message) { break }
            if companions.receive(packet.Message) { break }
            if packet.Message.hasPrefix(character.name + " : ") {
                mapScene?.showPublicChat(packet.Message, from: account.accountID)
            }
            let message = ChatMessage(from: packet)
            messageCenter.add(message)
        case let packet as PACKET_ZC_NPC_CHAT:
            let message = ChatMessage(from: packet)
            messageCenter.add(message)
        case let packet as PACKET_ZC_NOTIFY_CHAT_PARTY:
            let message = ChatMessage(from: packet)
            messageCenter.add(message)
        case let packet as PACKET_ZC_GUILD_CHAT:
            let message = ChatMessage(from: packet)
            messageCenter.add(message)
        case let packet as PACKET_ZC_NOTIFY_CLAN_CHAT:
            let message = ChatMessage(from: packet)
            messageCenter.add(message)
        case let packet as PetEvolutionResult:
            pets.finish(.evolve, message: packet.result == 6 ? "Pet evolution completed." : "Pet evolution rejected (\(packet.result)). Check intimacy and materials.")
        case let packet as BuyingStoreOpened:
            buyingStore.slots = min(5,Int(packet.slots)); buyingStore.draft = [:]; buyingStore.visible = true; buyingStore.message = nil
        case let packet as BuyingStoreRejected:
            buyingStore.waiting = nil; buyingStore.slots = 0; buyingStore.draft = [:]; buyingStore.message = "Cannot open the buying store (\(packet.result)). Check eligible items, weight and budget."
        case let packet as BuyingStoreEnded:
            buyingStore.active = false; buyingStore.own = nil; buyingStore.message = "Buying store ended (\(packet.reason))."
        case let packet as BuyingStoreSold: buyingStore.receive(packet, inventory: &inventory)
        case let packet as PACKET_ZC_BUYING_STORE_ENTRY:
            buyingStore.boards[packet.makerAID] = packet.storeName
            mapScene?.shopSigns[packet.makerAID] = "Buying: " + packet.storeName
        case let packet as PACKET_ZC_DISAPPEAR_BUYING_STORE_ENTRY:
            buyingStore.vanished(packet.makerAID); mapScene?.shopSigns.removeValue(forKey: packet.makerAID)
        case let packet as PACKET_ZC_ACK_ITEMLIST_BUYING_STORE:
            if buyingStore.browsing == packet.AID, buyingStore.sale == nil { buyingStore.shop = packet; buyingStore.waiting = nil; buyingStore.message = nil }
        case let packet as PACKET_ZC_MYITEMLIST_BUYING_STORE:
            if packet.AID == partyAccountID { buyingStore.own = packet; buyingStore.active = true; buyingStore.slots = 0; buyingStore.draft = [:]; buyingStore.waiting = nil; buyingStore.message = "Buying store opened." }
        case let packet as PACKET_ZC_UPDATE_ITEM_FROM_BUYING_STORE:
            if let i = buyingStore.own?.items.firstIndex(where: { $0.itemId == packet.itemId }) {
                let remaining = buyingStore.own?.items[i].amount ?? 0
                buyingStore.own?.items[i].amount = remaining >= packet.amount ? remaining - packet.amount : 0
                buyingStore.own?.zenyLimit = packet.zenyLimit
            }
        case let packet as PACKET_ZC_FAILED_TRADE_BUYING_STORE_TO_SELLER:
            if buyingStore.sale != nil { buyingStore.sale = nil; buyingStore.waiting = nil; buyingStore.shop = nil; buyingStore.message = "Sale rejected (\(packet.result))." }
        case let packet as PACKET_ZC_OPENSTORE:
            vending.preparingSlots = min(12,Int(packet.num)); vending.draft = [:]; vending.visible = true; vending.message = nil
        case let packet as PACKET_ZC_STORE_ENTRY:
            vending.boards[packet.makerAID] = .init(id: packet.makerAID, name: packet.storeName)
            mapScene?.shopSigns[packet.makerAID] = packet.storeName
        case let packet as PACKET_ZC_DISAPPEAR_ENTRY:
            vending.vanished(UInt32(bitPattern: packet.GID)); mapScene?.shopSigns.removeValue(forKey: UInt32(bitPattern: packet.GID))
        case let packet as PACKET_ZC_PC_PURCHASE_ITEMLIST_FROMMC: vending.receive(packet)
        case let packet as PACKET_ZC_PC_PURCHASE_MYITEMLIST:
            if packet.AID == partyAccountID { vending.own = packet.items; vending.active = true; vending.preparingSlots = 0; vending.draft = [:]; vending.waiting = nil; vending.message = "Shop opened." }
        case let packet as PACKET_ZC_ACK_OPENSTORE2:
            if packet.result != 0 { vending.waiting = nil; vending.message = "The server rejected this shop (\(packet.result))." }
        case let packet as PACKET_ZC_PC_PURCHASE_RESULT_FROMMC:
            if vending.purchase != nil { vending.purchase = nil; vending.waiting = nil; vending.shop = nil; vending.message = "Purchase rejected (\(packet.result))." }
        case let packet as PACKET_ZC_DELETEITEM_FROM_MCSTORE:
            if let i = vending.own.firstIndex(where: { UInt16(bitPattern: $0.index) == packet.index }) {
                vending.own[i].amount = max(0,vending.own[i].amount - Int16(clamping: packet.amount))
                vending.own.removeAll { $0.amount == 0 }
            }
        case let packet as RodexList: rodex.receive(packet)
        case let packet as RodexRead: rodex.receive(packet)
        case let packet as PACKET_ZC_ACK_OPEN_WRITE_MAIL:
            if rodex.pending == .begin {
                rodex.writing = packet.result != 0; rodex.attachments = [:]; rodex.receiver = nil
                rodex.finish(.begin, message: rodex.writing ? nil : "The server cannot open a letter now.")
            }
        case let packet as PACKET_ZC_CHECKNAME:
            if case let .check(requested) = rodex.pending {
                if packet.CharId > 0, packet.Name == requested { rodex.receiver = packet }
                rodex.finish(.check(requested), message: rodex.receiver == nil ? "Recipient not found." : "Recipient verified.")
            }
        case let packet as PACKET_ZC_ACK_ADD_ITEM_RODEX:
            if case let .attach(index) = rodex.pending {
                if packet.result == 0, Int(packet.index) == index, packet.count > 0 {
                    var item = packet; item.count += rodex.attachments[index]?.count ?? 0
                    rodex.attachments[index] = item
                }
                rodex.finish(.attach(index), message: packet.result == 0 ? nil : "Attachment rejected (\(packet.result)).")
            }
        case let packet as PACKET_ZC_ACK_REMOVE_ITEM_MAIL:
            let index = Int(packet.index)
            if rodex.pending == .remove(index) {
                if packet.result != 0 { rodex.attachments.removeValue(forKey: index) }
                rodex.finish(.remove(index), message: packet.result != 0 ? nil : "Cannot remove this attachment.")
            }
        case let packet as PACKET_ZC_WRITE_MAIL_RESULT:
            if rodex.pending == .send {
                rodex.finish(.send, message: packet.result == 0 ? "Mail sent." : "Mail was not sent (\(packet.result)).")
                sendFoundationPacket(RodexRequest.cancel); rodex.writing = false; rodex.attachments = [:]; rodex.receiver = nil
            }
        case let packet as PACKET_ZC_ACK_ZENY_FROM_MAIL:
            rodex.claim(id: UInt64(bitPattern: packet.MailID), items: false, result: packet.result)
        case let packet as PACKET_ZC_ACK_ITEM_FROM_MAIL:
            rodex.claim(id: UInt64(bitPattern: packet.MailID), items: true, result: packet.result)
        case let packet as PACKET_ZC_ACK_DELETE_MAIL:
            let id = UInt64(bitPattern: packet.MailID)
            if rodex.pending == .delete(id) { rodex.entries.removeAll { $0.id == id }; rodex.letter = nil; rodex.finish(.delete(id), message: "Mail deleted.") }
        case let packet as PACKET_ZC_MSG_COLOR:
            rewards.receiveAttendanceMessage(packet.MessageId)
        case let packet as PACKET_ZC_GUILD_SKILLINFO:
            if guild.id != nil { guild.skillPoints = packet.skillPoint; guild.skills = Dictionary(packet.skillInfo.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }) }
        case let packet as PACKET_ZC_MYGUILD_BASIC_INFO:
            if guild.id != nil { guild.relations = packet.rgInfo.filter { $0.GDID > 0 } }
        case let packet as PACKET_ZC_REQ_ALLY_GUILD:
            if guild.master { guild.allianceInvitation = packet; guild.visible = true }
        case let packet as PACKET_ZC_ACK_REQ_ALLY_GUILD:
            guild.finish(.alliance, message: packet.flag == 2 ? "Alliance accepted." : "Alliance request was not accepted (\(packet.flag)).")
            sendFoundationPacket(GuildRequest.page(0))
        case let packet as PACKET_ZC_DELETE_RELATED_GUILD:
            guild.relations.removeAll { UInt32(bitPattern: $0.GDID) == packet.allyID && UInt32(bitPattern: $0.relation) == packet.flag }
            guild.finish(.alliance, message: "Guild relationship removed.")
        case let packet as GuildEmblemPacket:
            receiveGuildEmblem(packet)
        case let packet as PACKET_ZC_CHANGE_GUILD:
            if guild.id == UInt32(bitPattern: packet.guild_id), packet.emblem_id > guild.emblemVersion {
                sendFoundationPacket(GuildRequest.emblem(UInt32(bitPattern: packet.guild_id)))
            }
        case let packet as GuildMemberStatus:
            if let index = guild.members.firstIndex(where: { $0.data.AID == packet.account && $0.data.GID == packet.character }) {
                guild.members[index].data.currentState = Int32(clamping: packet.online)
            }
        case let packet as PACKET_ZC_UPDATE_GDID:
            guild.receive(packet)
        case let packet as PACKET_ZC_GUILD_INFO:
            if packet.GDID > 0 {
                guild.id = UInt32(packet.GDID); guild.name = packet.guildname; guild.info = packet
                guild.master = UInt32(bitPattern: packet.masterGID) == character.charID
                if packet.emblemVersion > 0 && (guild.emblemBitmap == nil || UInt32(packet.emblemVersion) > guild.emblemVersion) {
                    sendFoundationPacket(GuildRequest.emblem(UInt32(packet.GDID)))
                }
                guild.finish(.join)
            }
        case let packet as PACKET_ZC_MEMBERMGR_INFO:
            if guild.id != nil { guild.receive(packet); guild.refreshPermissions(account: partyAccountID, character: character.charID) }
        case let packet as PACKET_ZC_POSITION_ID_NAME_INFO:
            guild.positionNames = Dictionary(packet.posInfo.map { ($0.positionID, $0.posName) }, uniquingKeysWith: { _, new in new })
        case let packet as PACKET_ZC_POSITION_INFO:
            guild.positions = Dictionary(packet.posInfo.map { ($0.positionID, $0) }, uniquingKeysWith: { _, new in new })
            guild.refreshPermissions(account: partyAccountID, character: character.charID)
        case let packet as PACKET_ZC_GUILD_NOTICE:
            guild.subject = packet.subject; guild.notice = packet.notice; guild.finish(.notice)
            if guild.pending == .join { openGuild() }
        case let packet as PACKET_ZC_RESULT_MAKE_GUILD:
            guild.finish(.create, message: packet.result == 0 ? "Guild created." : "Could not create the guild. Check its name and Emperium.")
            if packet.result == 0 { openGuild() }
        case let packet as PACKET_ZC_REQ_JOIN_GUILD:
            guild.invitation = packet; guild.visible = true
        case let packet as PACKET_ZC_ACK_REQ_JOIN_GUILD:
            guild.finish(.invite, message: packet.result == 2 ? "Invitation accepted." : "Invitation declined or unavailable (\(packet.result)).")
        case let packet as PACKET_ZC_ACK_LEAVE_GUILD2:
            guild.remove(characterID: packet.GID, ownID: character.charID)
        case let packet as PACKET_ZC_ACK_BAN_GUILD3:
            guild.remove(characterID: packet.GID, ownID: character.charID)
        case let packet as PACKET_ZC_ACK_DISORGANIZE_GUILD_RESULT:
            if packet.result == 0 { guild = GuildState(); guild.visible = true; guild.message = "Guild disbanded." }
            else { guild.finish(.disband, message: "The server rejected guild disbanding.") }
        case let packet as PACKET_ZC_ACK_REQ_CHANGE_MEMBERS:
            for row in packet.members {
                if let index = guild.members.firstIndex(where: { $0.data.AID == row.accId && $0.data.GID == row.charId }) { guild.members[index].data.positionID = row.positionID }
            }
            guild.refreshPermissions(account: partyAccountID, character: character.charID)
            guild.finish(.memberPosition)
        case let packet as PACKET_ZC_ACK_CHANGE_GUILD_POSITIONINFO:
            for row in packet.posInfo {
                guild.positionNames[row.positionID] = row.posName
                var value = PACKET_ZC_POSITION_INFO_sub(); value.positionID = row.positionID; value.right = row.mode; value.payRate = row.payRate; value.ranking = row.ranking
                guild.positions[row.positionID] = value
            }
            guild.refreshPermissions(account: partyAccountID, character: character.charID)
            guild.finish(.position)
        case let packet as PACKET_ZC_PROPERTY_HOMUN:
            followers.receive(packet)
        case let packet as PACKET_ZC_CHANGESTATE_MER:
            followers.receive(packet)
        case let packet as PACKET_ZC_HO_PAR_CHANGE:
            followers.homParameter(packet)
        case let packet as PACKET_ZC_FEED_MER:
            followers.finish(.feed, kind: .homunculus, message: packet.result == 0 ? "Could not feed the homunculus. Check its food." : "Homunculus fed.")
        case let packet as PACKET_ZC_HOSKILLINFO_LIST:
            followers.homSkills = Dictionary(packet.skills.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        case let packet as PACKET_ZC_HOSKILLINFO_UPDATE:
            followers.homSkills[packet.skill_id]?.level = UInt16(clamping: packet.Level)
            followers.homSkills[packet.skill_id]?.sp = UInt16(clamping: packet.SP)
            followers.homSkills[packet.skill_id]?.range = UInt16(clamping: packet.AttackRange)
            followers.homSkills[packet.skill_id]?.upgradable = UInt8(clamping: packet.upgradable)
            if followers.pendingSkill == packet.skill_id { followers.finish(.upgrade, kind: .homunculus) }
        case let packet as MercenaryInfo:
            followers.mercenary = packet
        case let packet as MercenarySkills:
            followers.mercSkills = Dictionary(packet.skills.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        case let packet as MercenaryParameter:
            followers.mercParameter(packet)
        case _ as PACKET_ZC_START_CAPTURE:
            pets.captureReady = true; pets.visible = true; pets.message = "Select a monster, then capture."
        case let packet as PACKET_ZC_TRYCAPTURE_MONSTER:
            pets.finish(.capture, message: packet.result == 1 ? "Capture succeeded." : "Capture failed or was cancelled.")
        case let packet as PACKET_ZC_PROPERTY_PET:
            pets.receive(packet)
        case let packet as PACKET_ZC_CHANGESTATE_PET:
            pets.receive(packet)
        case let packet as PACKET_ZC_FEED_PET:
            pets.finish(.feed, message: packet.result == 0 ? "Could not feed the pet. Check its food." : "Pet fed.")
        case let packet as PACKET_ZC_CONFIG:
            if packet.type == 2 { pets.autoFeed = packet.value != 0; pets.finish(.autoFeed) }
            if packet.type == 3 { followers.homAutoFeed = packet.value != 0; followers.finish(.autoFeed, kind: .homunculus) }
        case let packet as PACKET_ZC_ALL_ACH_LIST:
            rewards.receive(packet)
        case let packet as PACKET_ZC_ACH_UPDATE:
            rewards.receive(packet)
        case let packet as AchievementRewardResult:
            rewards.receive(packet)
        case let packet as PACKET_ZC_UI_OPEN_V3:
            if packet.type == 10, enchant.pending == nil {
                enchant = EnchantState(); enchant.visible = true; enchant.group = packet.data
                if enchant.recipe == nil { enchant.message = "This enchanter's recipes are not available yet." }
            }
        case let packet as PACKET_ZC_RESPONSE_ENCHANT:
            enchant.receive(packet, inventory: &inventory)
        case let packet as PACKET_ZC_UI_OPEN:
            if packet.UIType == 7 {
                rewards.attendanceVisible = true; rewards.attendanceAuthorized = true
                rewards.attendanceCount = Int(packet.data) / 10; rewards.attendanceClaimed = packet.data % 10 != 0
                rewards.attendanceWaiting = nil; rewards.attendanceMessage = nil
            }
        case let packet as AttendanceResult:
            if rewards.attendanceAuthorized {
                rewards.attendanceCount = Int(packet.count); rewards.attendanceClaimed = true
                rewards.attendanceWaiting = nil; rewards.attendanceMessage = "Reward sent to your mailbox."
            }
        case let packet as PACKET_ZC_NOTIFY_TIME:
            if let requestTime = serverTimeRequestTime {
                let now = ContinuousClock.now
                serverClock.synchronize(serverTick: packet.time, receiveTime: now, roundTripTime: requestTime.duration(to: now))
                serverTimeRequestTime = nil
            }
        case let packet as PACKET_SC_NOTIFY_BAN:
            let message = BannedMessage(from: packet)
            let localizedMessage = context.messageStringTable.localizedMessageString(forID: message.messageID)
            delegate?.playSession(self, didReceiveErrorMessage: localizedMessage)
        case let packet as PACKET_ZC_REQ_EXCHANGE_ITEM:
            if enchant.pending != nil || rodex.busy || buyingStore.busy || vending.active || vending.purchase != nil || trade.active || bank.pending != nil || cart.pending != nil || refine.pending != nil || itemSelection.pending != nil {
                sendFoundationPacket(TradeRequest.reply(false))
            } else {
                trade = TradeState(); trade.visible = true; trade.invitation = true
                trade.partnerID = packet.targetId; trade.partnerName = packet.requesterName
            }
        case let packet as PACKET_ZC_ACK_EXCHANGE_ITEM:
            trade.waiting = nil; trade.invitation = false
            if packet.result == 3 {
                trade.active = true; trade.visible = true; trade.partnerID = packet.targetId; trade.message = nil
            } else { trade.finish("Trade unavailable or declined (\(packet.result)).") }
        case let packet as PACKET_ZC_ACK_ADD_EXCHANGE_ITEM:
            trade.receiveAdd(packet, inventory: &inventory)
        case let packet as PACKET_ZC_ADD_EXCHANGE_ITEM:
            trade.receiveOther(packet)
        case let packet as PACKET_ZC_CONCLUDE_EXCHANGE_ITEM:
            if trade.active {
                if packet.who == 0 { trade.locked = true; trade.waiting = nil; trade.message = nil }
                else { trade.otherLocked = true }
            }
        case _ as PACKET_ZC_CANCEL_EXCHANGE_ITEM:
            trade.finish("Trade cancelled.")
        case let packet as PACKET_ZC_EXEC_EXCHANGE_ITEM:
            trade.finish(packet.result == 0 ? "Trade completed." : "Trade failed.")
        case _ as PACKET_ZC_EXCHANGEITEM_UNDO:
            trade.locked = false; trade.otherLocked = false; trade.waiting = nil
        case _ as PACKET_ZC_ACK_OPEN_BANKING:
            bankOpened()
        case let packet as PACKET_ZC_BANKING_CHECK:
            bankChecked(packet)
        case let packet as PACKET_ZC_ACK_BANKING_DEPOSIT:
            bank.receive(operation: .deposit, reason: packet.reason, money: packet.money)
            if packet.zeny >= 0 { playerStatus.zeny = Int(packet.zeny) }
        case let packet as PACKET_ZC_ACK_BANKING_WITHDRAW:
            bank.receive(operation: .withdraw, reason: packet.reason, money: packet.money)
            if packet.zeny >= 0 { playerStatus.zeny = Int(packet.zeny) }
        case _ as PACKET_ZC_ACK_CLOSE_BANKING:
            bank.authorized = false
        case let packet as PACKET_ZC_FRIENDS_LIST:
            social.receive(packet)
        case let packet as PACKET_ZC_FRIENDS_STATE:
            social.receive(packet)
        case let packet as FriendInvitation:
            social.invitation = .init(accountID: packet.accountID, characterID: packet.characterID, name: packet.name, online: true)
            social.friendsVisible = true
        case let packet as FriendAdded:
            social.receive(packet)
        case let packet as FriendRemoved:
            social.receive(packet)
        case let packet as PACKET_ZC_ACK_WHISPER:
            receiveWhisperResult(packet)
        case _ as PACKET_ZC_EXTEND_BODYITEM_SIZE:
            break
        case _ as PACKET_ZC_STATUS_CHANGE_ACK:
            break
        case let packet as PACKET_ZC_NOTIFY_CARTITEM_COUNTINFO:
            cart.receiveCount(packet)
        case let packet as PACKET_ZC_ADD_ITEM_TO_CART:
            cart.receiveAdded(packet)
        case let packet as PACKET_ZC_DELETE_ITEM_FROM_CART:
            cart.receiveRemoved(packet)
        case _ as PACKET_ZC_CARTOFF:
            cart = CartState()
        case let packet as PACKET_ZC_ACK_ADDITEM_TO_CART:
            cart.pending = nil
            cart.message = packet.result == 0 ? "Cart weight limit reached." : "Cart item limit reached."
        case _ as PACKET_ZC_PARTY_CONFIG:
            break
        case _ as PACKET_ZC_REPUTE_INFO:
            break
        case _ as PACKET_ZC_BROADCAST:
            break
        case _ as PACKET_ZC_BROADCAST2:
            break
        default:
            break
        }
    }

    /// Keep alive and synchronize the server clock.
    ///
    /// Send ``PACKET_CZ_REQUEST_TIME`` every second for the first 5 seconds, then every 10 seconds.
    /// The map server drops it until the map is loaded, so it restarts after each map load.
    private func startKeepalive() {
        guard let mapClient else {
            return
        }

        let startTime = ContinuousClock.now

        keepaliveTask?.cancel()
        keepaliveTask = Task {
            var requestCount = 0
            while !Task.isCancelled {
                let now = ContinuousClock.now
                let clientTime = Int(startTime.duration(to: now).timeInterval * 1000)
                serverTimeRequestTime = now

                let packet = PacketFactory.CZ_REQUEST_TIME(clientTime: UInt32(truncatingIfNeeded: clientTime))
                mapClient.sendPacket(packet)

                try? await Task.sleep(for: requestCount < 5 ? .seconds(1) : .seconds(10))
                requestCount += 1
            }
        }
    }

    // MARK: - Map Operations

    func requestExamRoom() {
        guard canAccessExamRoom, let examRoomID, let mapClient else { return }
        switch examQueueState {
        case .idle, .refused:
            var request = PACKET_CZ_REQ_ENTER_ROOM()
            request.packetType = HEADER_CZ_REQ_ENTER_ROOM
            request.chat_id = examRoomID
            request.password = ""
            examQueueState = .joining
            mapClient.sendPacket(request)
        case .queued:
            examQueueState = .leaving
            mapClient.sendPacket(LeaveWaitingRoomRequest())
        case .joining, .leaving:
            break
        }
    }

    func notifyMapLoaded() {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_NOTIFY_ACTORINIT()
        mapClient.sendPacket(packet)

        startKeepalive()
    }

    func resurrectInPlace() {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_STANDING_RESURRECTION()
        mapClient.sendPacket(packet)
    }

    func returnToLastSavePoint() {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_RESTART(type: 0)
        mapClient.sendPacket(packet)
    }

    func returnToCharacterSelect() {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_RESTART(type: 1)
        mapClient.sendPacket(packet)
    }

    var partyAccountID: UInt32 { account.accountID }

    func companionCommand(_ action: String) {
        guard !companions.pending, action == "list" || (companions.ready && companions.available) else { return }
        let token = companions.begin(action)
        let capability = action.hasPrefix("inspect ") ? "ui2 skills9 gear3 syrup1" : "ui2"
        sendMessage("@companion ui \(token) \(action) \(capability) hunter1 voice1 bird1 phase1 loop1 puller1 team2 radius1 hunt1")
        companionTimeout?.cancel()
        companionTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.companions.timeout(token)
        }
    }

    func setPartyOptions(exp: Bool, pickup: Bool, distribution: Bool) {
        guard party.optionsReady, !party.optionsPending,
              party.members.contains(where: { $0.id == account.accountID && $0.leader }) else { return }
        party.optionsPending = true
        party.shareMessage = "Waiting for server confirmation…"
        mapClient?.sendPacket(PartyOptionsRequest(exp: exp, pickup: pickup, distribution: distribution))
        partyOptionsTimeout?.cancel()
        partyOptionsTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, self.party.optionsPending else { return }
            self.party.optionsPending = false
            self.party.shareMessage = "No confirmation received. Reopen the party window or reconnect before retrying."
        }
    }

    func leaveParty() {
        guard party.members.contains(where: { $0.id == account.accountID }) else { return }
        var packet = PACKET_CZ_REQ_LEAVE_GROUP()
        packet.packetType = 0x100
        mapClient?.sendPacket(packet)
    }

    func expelPartyMember(_ member: PartyMember) {
        guard member.id != account.accountID,
              party.members.contains(where: { $0.id == account.accountID && $0.leader }),
              party.members.contains(where: { $0.id == member.id && $0.characterID == member.characterID }) else { return }
        var packet = PACKET_CZ_REQ_EXPEL_GROUP_MEMBER()
        packet.packetType = 0x103; packet.AID = member.id; packet.name = member.name
        mapClient?.sendPacket(packet)
    }

    func openCashShop() {
        cashShop.ready = false
        if !cashShop.pending { cashShop.message = nil }
        mapClient?.sendPacket(CashShopRequest(.list))
        var packet = PACKET_CZ_SE_CASHSHOP_OPEN2()
        packet.packetType = HEADER_CZ_SE_CASHSHOP_OPEN2
        packet.tab = cashShop.checkingBalance ? CashShopState.balanceCheckTab : 6
        mapClient?.sendPacket(packet)
    }

    func closeCashShop() {
        mapClient?.sendPacket(CashShopRequest(.close))
        cashShop.ready = false
    }

    func applyQuestPacket(_ packet: QuestWirePacket) {
        quests = QuestLogDecoder.applying(packet, to: quests)
        if let id = questUI.selectedQuestID, quests[id] == nil { questUI.selectedQuestID = nil }
    }

    func setQuestActive(_ questID: UInt32, active: Bool) {
        guard let quest = quests[questID], quest.state != 2 else { return }
        mapClient?.sendPacket(QuestActiveRequest(questID: questID, active: active))
        // The server's 0x02b7 acknowledgement updates the authoritative state.
    }

    func buyCashShopCart(freePoints: UInt32) {
        guard let mapClient,
              let packet = cashShop.beginCartPurchase(freePoints: freePoints) else { return }
        mapClient.sendPacket(packet)
        scheduleCashShopTimeout()
    }

    private func scheduleCashShopTimeout() {
        cashShopTimeout?.cancel()
        cashShopTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, cashShop.purchaseTimeout() else { return }
            var balance = PACKET_CZ_SE_CASHSHOP_OPEN2()
            balance.packetType = HEADER_CZ_SE_CASHSHOP_OPEN2
            balance.tab = CashShopState.balanceCheckTab
            mapClient?.sendPacket(balance)
        }
    }

    func requestExit() {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_REQUEST_QUIT()
        mapClient.sendPacket(packet)
    }

    // MARK: - Player

    /// Request move to position.
    ///
    /// Send ``PACKET_CZ_REQUEST_MOVE``
    func requestMove(to position: SIMD2<Int>) {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_REQUEST_MOVE(position: position)
        mapClient.sendPacket(packet)
    }

    /// Request action on target.
    ///
    /// Send ``PACKET_CZ_REQUEST_ACT``
    func requestAction(_ actionType: DamageType, onTarget targetID: GameObjectID = 0) {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_REQUEST_ACT(targetID: targetID, actionType: actionType)
        mapClient.sendPacket(packet)
    }

    /// Change direction.
    ///
    /// Send ``PACKET_CZ_CHANGE_DIRECTION``
    ///
    /// Receive ``PACKET_ZC_CHANGE_DIRECTION``
    func changeDirection(direction: Direction, headDirection: HeadDirection) {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_CHANGE_DIRECTION(
            headDirection: UInt16(headDirection.rawValue),
            direction: UInt8(direction.rawValue)
        )
        mapClient.sendPacket(packet)
    }

    func incrementStatusProperty(_ sp: StatusProperty, by amount: Int) {
        guard let mapClient else {
            return
        }

        switch sp {
        case .str, .agi, .vit, .int, .dex, .luk:
            let packet = PacketFactory.CZ_STATUS_CHANGE(property: sp, amount: amount)
            mapClient.sendPacket(packet)
        case .pow, .sta, .wis, .spl, .con, .crt:
            let packet = PacketFactory.CZ_ADVANCED_STATUS_CHANGE(property: sp, amount: amount)
            mapClient.sendPacket(packet)
        default:
            break
        }
    }

    func upgradeSkillLevel(skillID: Int) {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_UPGRADE_SKILLLEVEL(skillID: skillID)
        mapClient.sendPacket(packet)
    }

    func useSkill(skillID: Int, level: Int, onTarget targetID: GameObjectID) {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_USE_SKILL(
            skillID: skillID,
            selectedLevel: max(level, 1),
            targetID: targetID
        )
        mapClient.sendPacket(packet)
    }

    func useSkill(skillID: Int, level: Int, toGround position: SIMD2<Int>) {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_USE_SKILL_TOGROUND(
            skillID: skillID,
            selectedLevel: max(level, 1),
            position: position
        )
        mapClient.sendPacket(packet)
    }

    func selectWarpPoint(mapName: String) {
        guard let mapClient, let warpList else {
            return
        }

        let packet = PacketFactory.CZ_SELECT_WARPPOINT(skillID: warpList.skillID, mapName: mapName)
        mapClient.sendPacket(packet)

        self.warpList = nil
    }

    func cancelWarpPoint() {
        selectWarpPoint(mapName: "cancel")
    }

    // MARK: - Item

    func pickUpItem(objectID: GameObjectID) {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_ITEM_PICKUP(objectID: objectID)
        mapClient.sendPacket(packet)
    }

    func useItem(at index: Int) {
        guard !hasPendingInventoryOperation else { return }
        guard enchant.pending == nil, !buyingStore.busy, !vending.active, vending.purchase == nil, !rodex.busy, !trade.active, trade.waiting == nil else { return }
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_USE_ITEM(index: index, accountID: account.accountID)
        mapClient.sendPacket(packet)
    }

    func sendFoundationPacket(_ packet: any EncodablePacket) {
        mapClient?.sendPacket(packet)
    }

    func equipItem(at index: Int, location: EquipPositions) {
        guard !hasPendingInventoryOperation else { return }
        guard enchant.pending == nil, !buyingStore.busy, !vending.active, vending.purchase == nil, !rodex.busy, !trade.active, trade.waiting == nil else { return }
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_REQ_WEAR_EQUIP(index: index, location: location)
        mapClient.sendPacket(packet)
    }

    func unequipItem(at index: Int) {
        guard !hasPendingInventoryOperation else { return }
        guard enchant.pending == nil, !buyingStore.busy, !vending.active, vending.purchase == nil, !rodex.busy, !trade.active, trade.waiting == nil else { return }
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_REQ_TAKEOFF_EQUIP(index: index)
        mapClient.sendPacket(packet)
    }

    func throwItem(at index: Int, amount: Int) {
        guard !hasPendingInventoryOperation else { return }
        guard enchant.pending == nil, !buyingStore.busy, !vending.active, vending.purchase == nil, !rodex.busy, !trade.active, trade.waiting == nil else { return }
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_ITEM_THROW(index: index, amount: amount)
        mapClient.sendPacket(packet)
    }

    // MARK: - Shortcut

    func useShortcut(_ shortcut: Shortcut, gamepadTarget: GameObjectID? = nil, gamepadValidation: GamepadTargetValidation? = nil) {
        switch shortcut {
        case .empty:
            break
        case .item(let itemID):
            if let item = inventory.items.values.first(where: { $0.itemID == itemID }) {
                useItem(at: item.index)
            }
        case .skill(let skillID, let level):
            if let skill = skillList.skills[skillID] {
                if let gamepadTarget {
                    mapScene?.useGamepadSkill(skill, level: level, targetID: gamepadTarget, validate: gamepadValidation)
                } else { mapScene?.useSkill(skill, level: level) }
            }
        }
    }

    func setShortcut(_ shortcut: Shortcut, atRow row: Int, column: Int) {
        guard let mapClient else {
            return
        }

        var shortcutList = self.shortcutList
        shortcutList.setShortcut(shortcut, atRow: row, column: column)

        for change in shortcutList.changes(from: self.shortcutList) {
            let packet = PacketFactory.CZ_SHORTCUT_KEY_CHANGE2(change: change)
            mapClient.sendPacket(packet)
        }

        self.shortcutList = shortcutList
    }

    func removeShortcut(atRow row: Int, column: Int) {
        setShortcut(.empty, atRow: row, column: column)
    }

    func moveShortcut(
        _ shortcut: Shortcut,
        fromRow sourceRow: Int,
        column sourceColumn: Int,
        toRow targetRow: Int,
        column targetColumn: Int
    ) {
        guard let mapClient,
              shortcutList.rows[sourceRow][sourceColumn] == shortcut else {
            return
        }

        var shortcutList = self.shortcutList
        shortcutList.setShortcut(.empty, atRow: sourceRow, column: sourceColumn)
        shortcutList.setShortcut(shortcut, atRow: targetRow, column: targetColumn)

        for change in shortcutList.changes(from: self.shortcutList) {
            let packet = PacketFactory.CZ_SHORTCUT_KEY_CHANGE2(change: change)
            mapClient.sendPacket(packet)
        }

        self.shortcutList = shortcutList
    }

    func setShortcutRowShift(_ rowShift: Int) {
        guard let mapClient else {
            return
        }

        shortcutList.rowShift = rowShift

        let packet = PacketFactory.CZ_SHORTCUTKEYBAR_ROTATE2(rowShift: rowShift)
        mapClient.sendPacket(packet)
    }

    // MARK: - Chat

    func sendMessage(_ message: String) {
        guard let mapClient else {
            return
        }

        if message.hasPrefix("%") {
            _ = sendSocialText(String(message.dropFirst()).trimmingCharacters(in: .whitespaces), channel: .party)
        } else if message.hasPrefix("$") {
            _ = sendSocialText(String(message.dropFirst()).trimmingCharacters(in: .whitespaces), channel: .guild)
        } else if message.lowercased().hasPrefix("/r ") {
            if let recipient = social.lastWhisperSender {
                _ = sendSocialText(String(message.dropFirst(3)), channel: .whisper, recipient: recipient)
            } else { socialMessage("No whisper sender to reply to.") }
        } else if message.hasPrefix("/cl") {
//            PACKET_CZ_CLAN_CHAT
        } else if message.hasPrefix("/") {
            performSlashCommand(message)
        } else {
            let packet = PacketFactory.CZ_REQUEST_CHAT(message: "\(character.name) : \(message)")
            mapClient.sendPacket(packet)
        }
    }

    @ObservationIgnored private var checkingGroundEffects = false

    private func performSlashCommand(_ message: String) {
        if message.lowercased() == "/effectfiles" {
            guard !checkingGroundEffects else { return }
            checkingGroundEffects = true
            messageCenter.messages.append(.init(content: "กำลังตรวจไฟล์เอฟเฟกต์ในไคลเอนต์…", type: .info, category: .general))
            Task {
                defer { checkingGroundEffects = false }
                await GroundEffectFiles.inspect(context.resourceManager) { line in
                    messageCenter.messages.append(.init(content: line, type: .info, category: .general))
                }
            }
            return
        }
        guard let slashCommand = SlashCommand(message: message) else {
            messageCenter.addUnknownSlashCommandMessage()
            return
        }

        switch slashCommand {
        case .where:
            if let mapScene {
                let mapName = mapScene.mapName.replacingOccurrences(of: ".rsw", with: "")
                let localizedMapName = context.mapInfoTable.localizedMapName(forMapName: mapName) ?? mapName
                messageCenter.addLocationMessage(mapName: mapName, localizedMapName: localizedMapName, position: mapScene.player.gridPosition)
            }
        case .sit, .stand:
            mapScene?.toggleSit()
        case .help:
            messageCenter.addSlashCommandHelpMessages()
        }
    }

    // MARK: - NPC Dialog

    func talkToNPC(npcID: GameObjectID) {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_CONTACTNPC(npcID: npcID)
        mapClient.sendPacket(packet)
    }

    func requestNextMessage() {
        guard let mapClient, let npcID = dialog?.npcID else {
            return
        }

        let packet = PacketFactory.CZ_REQ_NEXT_SCRIPT(npcID: npcID)
        mapClient.sendPacket(packet)

        dialog?.setNeedsClearMessage()
        dialog?.clearAction()
    }

    func closeDialog() {
        guard let mapClient, let npcID = dialog?.npcID else {
            return
        }

        dialog = nil

        let packet = PacketFactory.CZ_CLOSE_DIALOG(npcID: npcID)
        mapClient.sendPacket(packet)
    }

    func selectMenu(_ select: UInt8) {
        guard let mapClient, let npcID = dialog?.npcID else {
            return
        }

        dialog?.clearMenu()

        let packet = PacketFactory.CZ_CHOOSE_MENU(npcID: npcID, select: select)
        mapClient.sendPacket(packet)
    }

    func cancelMenu() {
        guard let mapClient, let npcID = dialog?.npcID else {
            return
        }

        dialog = nil

        let packet = PacketFactory.CZ_CHOOSE_MENU(npcID: npcID, select: 255)
        mapClient.sendPacket(packet)
    }

    func confirmInput(_ value: Int32) {
        guard let mapClient, let npcID = dialog?.npcID else {
            return
        }

        let packet = PacketFactory.CZ_INPUT_EDITDLG(npcID: npcID, value: value)
        mapClient.sendPacket(packet)

        dialog?.clearInput()
    }

    func confirmInput(_ value: String) {
        guard let mapClient, let npcID = dialog?.npcID else {
            return
        }

        let packet = PacketFactory.CZ_INPUT_EDITDLGSTR(npcID: npcID, value: value)
        mapClient.sendPacket(packet)

        dialog?.clearInput()
    }

    // MARK: - NPC Shop

    func selectDealType(_ dealType: NPCShopDealType) {
        guard let mapClient, let npcID = dealSelectionNPCID else {
            return
        }

        dealSelectionNPCID = nil

        let packet = PacketFactory.CZ_ACK_SELECT_DEALTYPE(npcID: npcID, dealType: dealType)
        mapClient.sendPacket(packet)
    }

    func cancelDealSelection() {
        dealSelectionNPCID = nil
    }

    func purchaseItems(_ purchases: [NPCShopPurchase]) {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_PC_PURCHASE_ITEMLIST(purchases: purchases)
        mapClient.sendPacket(packet)
    }

    func sellItems(_ sales: [NPCShopSale]) {
        guard let mapClient else {
            return
        }

        let packet = PacketFactory.CZ_PC_SELL_ITEMLIST(sales: sales)
        mapClient.sendPacket(packet)
    }

    func closeNPCShop() {
        guard let mapClient else {
            return
        }

        npcShop = nil

        let packet = PacketFactory.CZ_NPC_TRADE_QUIT()
        mapClient.sendPacket(packet)
    }

    // MARK: - Storage

    func moveItemToStorage(index: Int, amount: Int) {
        guard !hasPendingInventoryOperation else { return }
        guard enchant.pending == nil, !buyingStore.busy, !vending.active, vending.purchase == nil, !rodex.busy, !trade.active, trade.waiting == nil else { return }
        guard let mapClient, storage != nil else {
            return
        }

        let packet = PacketFactory.CZ_MOVE_ITEM_FROM_BODY_TO_STORE(index: index, amount: amount)
        mapClient.sendPacket(packet)
    }

    func moveItemFromStorage(index: Int, amount: Int) {
        guard !hasPendingInventoryOperation else { return }
        guard enchant.pending == nil, !buyingStore.busy, !vending.active, vending.purchase == nil, !rodex.busy, !trade.active, trade.waiting == nil else { return }
        guard let mapClient, storage != nil else {
            return
        }

        let packet = PacketFactory.CZ_MOVE_ITEM_FROM_STORE_TO_BODY(index: index, amount: amount)
        mapClient.sendPacket(packet)
    }

    func closeStorage() {
        guard let mapClient else {
            return
        }

        storage = nil

        let packet = PacketFactory.CZ_CLOSE_STORE()
        mapClient.sendPacket(packet)
    }
}

extension PlaySession {
    /// An item which is no longer in the inventory is dimmed, and cannot be used.
    func isShortcutAvailable(_ shortcut: Shortcut) -> Bool {
        switch shortcut {
        case .empty, .skill:
            true
        case .item(let itemID):
            inventory.items.values.contains(where: { $0.itemID == itemID })
        }
    }

    /// The number shown beside the icon: how many of an item are left, or the level a skill is used at.
    func shortcutLabel(_ shortcut: Shortcut) -> String? {
        switch shortcut {
        case .empty:
            nil
        case .item(let itemID):
            inventory.items.values.first(where: { $0.itemID == itemID }).map({ "\($0.amount)" })
        case .skill(_, let level):
            "\(level)"
        }
    }

    func skillCooldown(for shortcut: Shortcut) -> SkillCooldown? {
        switch shortcut {
        case .empty, .item:
            nil
        case .skill(let skillID, _):
            skillCooldowns[skillID]
        }
    }
}

extension PlaySession {
    static let testing = PlaySession(context: .testing)

    convenience init(context: GameContext) {
        self.init(
            context: context,
            audioPlayer: GameAudioPlayer(resourceManager: context.resourceManager),
            account: AccountInfo(from: PACKET_AC_ACCEPT_LOGIN()),
            character: CharacterInfo()
        )
    }
}
