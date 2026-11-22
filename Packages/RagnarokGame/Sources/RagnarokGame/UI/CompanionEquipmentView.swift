import RagnarokConstants
import RagnarokModels
import RagnarokSprite
import RagnarokResources
import SwiftUI

/// Original game skin, bounded controls and server-authoritative companion details.
struct CompanionEquipmentView: View {
    let profileID: UInt32
    var close: () -> Void
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var showActivity = false
    @State private var tab = 0
    @State private var selection = ""
    @State private var allowedSkills: [String]?
    @State private var needsPolicy = false
    @State private var quantity = 10
    @State private var waitingForTransfer = false
    @State private var feedback = "Loading companion…"
    private var state: CompanionState { session.companions }
    private var profile: CompanionProfile? { state.profiles.first { $0.id == profileID } }
    private var ready: Bool { state.ready && state.available && state.equipmentReady && state.detailReady && state.equipmentProfile == profileID && !state.pending && !state.transferPending }
    private var gear: CompanionEquipment? { state.equipment.first { selection == "gear:\($0.id)" } }
    private var bagItem: CompanionBagItem? { state.bag.first { selection == "bag:\($0.id):\($0.uniqueID)" } }
    private var supply: CompanionSupply? { state.supplies.first { selection == "supply:\($0.id)" } }
    private var supplyBag: CompanionSupply? { state.supplyBag.first { selection == "supplybag:\($0.id):\($0.itemID)" } }
    private var amount: Int { min(quantity, Int(supplyBag?.amount ?? supply?.amount ?? 1)) }

    var body: some View {
        GeometryReader { viewport in
            ClassicGamePanel(title: profile?.name ?? "Companion Details", width: 356, height: min(420, max(300, viewport.size.height - 24)), tracksCompanion: true, onClose: close) {
            VStack(spacing: 5) {
                HStack {
                    Text([profile?.jobName, profile?.build.map(companionBuildTitle)].compactMap { $0 }.joined(separator: " · ")).font(.game(weight: .bold))
                    Spacer()
                    Button("Info") { showActivity = true }.buttonStyle(.game).frame(width: 38, height: 24)
                    Text("Lv \(profile?.level ?? 0)/\(profile?.jobLevel ?? 0) · \(profile?.stateName ?? "…")").font(.game(size: 10))
                }.padding(.trailing, 26).frame(height: 24)
                HStack(spacing: 2) {
                    tabButton("Gear", index: 0); tabButton("Skills", index: 1)
                    tabButton("Supplies", index: 2); tabButton("Your Bag", index: 3)
                }.frame(height: 28)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if state.equipmentProfile == profileID && (state.detailReady || (state.pending && state.action == "inspect \(profileID)")) {
                            switch tab {
                            case 0:
                                equipmentDiagram
                                if !storedRows.isEmpty {
                                    Text("Stored & fallback").font(.game(size: 10)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                                }
                                itemGrid {
                                    ForEach(storedRows) { row in
                                        itemCell(row.id, row.itemID, quantity: row.details.refine > 0 ? "+\(row.details.refine)" : "")
                                    }
                                }
                            case 1:
                                ForEach(state.skills) { skill in
                                    HStack(spacing: 6) {
                                        CompanionSkillIcon(id: skill.id).frame(width: 26, height: 26)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(skill.name).font(.game(weight: .bold))
                                            Text(skill.isPassive ? "Passive · Job \(skill.unlock)" : "\(skill.status) · SP \(skill.sp)").font(.game(size: 10))
                                        }
                                        Spacer()
                                        Text("\(skill.level)/\(skill.maximum)").font(.game(size: 11))
                                        if let key = skill.policyKey, let order = allowedSkills {
                                            Button(order.contains(key) ? "AI On" : "AI Off") {
                                                let updated = skill.toggling(in: order)
                                                send("skills \(profileID) \(updated.isEmpty ? "none" : updated.joined(separator: ","))")
                                            }.buttonStyle(.game).frame(width: 48, height: 28).disabled(!ready)
                                        }
                                    }.padding(.horizontal, 5).frame(minHeight: 36)
                                    Divider()
                                }
                            case 2:
                                if let profile, [4,8].contains(profile.job) {
                                    let deposited = state.supplies.first { $0.itemID == 717 }?.amount ?? 0
                                    Text("Blue Gemstone: \(profile.gems + deposited) · Starter: \(profile.gems) · Returnable: \(deposited)")
                                        .font(.game(size: 11))
                                }
                                itemGrid {
                                    ForEach(state.supplies) { item in itemCell("supply:\(item.id)", item.itemID, quantity: String(item.amount)) }
                                }
                                if state.supplies.isEmpty { empty(state.suppliesAvailable ? "No supplies. Reserve, then give supplies from Your Bag. Hunters also accept arrows." : "Supplies are not enabled on this server.") }
                            default:
                                itemGrid {
                                    ForEach(state.supplyBag) { item in itemCell("supplybag:\(item.id):\(item.itemID)", item.itemID, quantity: String(item.amount)) }
                                    ForEach(state.bag) { item in itemCell("bag:\(item.id):\(item.uniqueID)", item.itemID, quantity: item.blockedReason != nil ? "×" : "") }
                                }
                                if state.bag.isEmpty && state.supplyBag.isEmpty { empty("No eligible items. Transferable equipment and supported supplies only.") }
                            }
                        } else { empty(state.pending ? "Loading…" : "Waiting to refresh companion details.") }
                    }
                }.frame(maxHeight: .infinity).overlay { Rectangle().strokeBorder(Color.gameBoxBorder).allowsHitTesting(false) }
                if let selectedItem {
                    Text(selectedItem).font(.game(size: 11)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 5) {
                    if tab == 0 {
                        control(gear?.equipped == true ? "Unequip" : "Equip", disabled: !ready || profile?.mode != 3 || gear == nil || gear?.returning == true) {
                            if let gear { send("\(gear.equipped ? "unequip" : "equip") \(profileID) \(gear.id)") }
                        }
                        control("Return", disabled: !ready || profile?.active != false || gear == nil || gear?.returning == true) {
                            if let gear { send("take \(profileID) \(gear.id)") }
                        }
                    } else if tab == 2 || tab == 3 {
                        if supply != nil || supplyBag != nil {
                            control("−", disabled: quantity <= 1) { quantity = max(1, quantity - 1) }
                            Text("\(amount)").font(.game(size: 12)).frame(width: 32)
                            control("+", disabled: quantity >= min(100,Int(supplyBag?.amount ?? supply?.amount ?? 1))) { quantity += 1 }
                        }
                        control(tab == 2 ? "Return" : "Give", disabled: !ready || profile?.active != false || (tab == 2 ? supply == nil : (bagItem == nil || bagItem?.blockedReason != nil) && supplyBag == nil)) {
                            if tab == 2, let supply { send("supplytake \(profileID) 0:\(supply.itemID):0:\(amount)") }
                            else if let item = supplyBag { send("supplygive \(profileID) \(item.id):\(item.itemID):\(item.amount):\(amount)") }
                            else if let item = bagItem { send("giveui \(profileID) \(item.id):\(item.uniqueID)") }
                        }
                    }
                    Spacer(minLength: 1)
                    control("Refresh", disabled: state.pending) { refresh() }
                }.frame(height: 30)
                if tab == 2 || tab == 3, let rule = state.potionRule {
                    Text(rule).font(.game(size: 10)).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !feedback.isEmpty {
                    Text(feedback).font(.game(size: 10)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(6)
            }
        }
        .alert("Activity", isPresented: $showActivity) {
            Button("OK") {}
        } message: { Text(state.activity) }
        .onChange(of: tab) {
            selection = ""
            feedback = ""
            if tab == 1 {
                allowedSkills = nil
                needsPolicy = true
                if !state.pending && state.ready { fetchPolicy() }
            }
        }
        .onChange(of: selection) { quantity = min(10, Int(supplyBag?.amount ?? supply?.amount ?? 10)) }
        .onChange(of: state.completedSequence) {
            guard !state.pending else { return }
            if state.action == "config \(profileID)" || state.action.hasPrefix("skills \(profileID) ") {
                let prefix = "Companion \(profileID) role="
                if state.message.hasPrefix(prefix), let range = state.message.range(of: " skills=") {
                    let order = state.message[range.upperBound...]
                    allowedSkills = order == "none" ? [] : order.split(separator: ",").map(String.init)
                } else { allowedSkills = nil }
                if tab == 1 { feedback = allowedSkills == nil ? state.message : "" }
                if state.ready { refresh() }
            } else if state.action.hasPrefix("inspect ") {
                if tab == 1 && needsPolicy && state.ready { fetchPolicy(); return }
                if waitingForTransfer || state.transferPending || feedback == "Loading companion…" { feedback = state.message }
                waitingForTransfer = state.transferPending
            } else {
                feedback = state.message; waitingForTransfer = state.message.contains("Waiting for inventory")
                if state.ready { refresh() }
            }
        }
        .task {
            while state.pending && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
            guard !Task.isCancelled else { return }; refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
                refresh()
            }
        }
    }
    private func itemName(_ id: UInt32) -> String {
        let name = context.itemInfoTable.localizedIdentifiedItemName(forItemID: Int(id))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.flatMap { $0.isEmpty ? nil : $0 } ?? "Item #\(id)"
    }

    private var selectedItem: String? {
        var id: UInt32
        var detail: String
        var info = CompanionItemDetails.plain
        if let row = state.gearRows.first(where: { $0.id == selection }) {
            id = row.itemID; info = row.details; detail = row.detail
            if gear != nil && profile?.mode != 3 && profile?.active == true { detail += " · Stop to equip" }
        } else if let item = bagItem {
            id = item.itemID; info = item.details; detail = item.blockedReason ?? (profile?.active == true ? "Reserve to give" : "Equipment")
        } else if let item = supplyBag ?? supply {
            id = item.itemID; detail = "×\(item.amount)" + (profile?.active == true ? " · Reserve to transfer" : "")
        } else { return nil }
        let name = (info.refine > 0 ? "+\(info.refine) " : "") + itemName(id)
        return ([name,detail] + info.cards.map(itemName)).joined(separator: " · ")
    }

    private var storedRows: [CompanionGearRow] {
        let equipped = Set(state.equipment.filter { $0.equipMask & 0x3ff != 0 }.map { "gear:\($0.id)" }
            + state.starters.filter(\.equipped).map { "starter:\($0.id)" })
        return state.gearRows.filter { !equipped.contains($0.id) }
    }

    private var equipmentDiagram: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                slot("Head", .head_top); slot("Middle", .head_mid); slot("R-hand", .right_hand)
                slot("Robe", .garment); slot("Acc. 1", .right_accessory)
            }
            CompanionMannequin(job: profile?.job ?? 0).frame(width: 72)
            VStack(spacing: 0) {
                slot("Lower", .head_low); slot("Body", .armor); slot("L-hand", .left_hand)
                slot("Shoes", .shoes); slot("Acc. 2", .left_accessory)
            }
        }.frame(height: 140).border(Color.gameBoxBorder)
    }

    private func slot(_ label: String, _ position: EquipPositions) -> some View {
        let owned = state.equipment.first { $0.equipMask & UInt32(position.rawValue) != 0 }
        let starter = state.starters.first { $0.equipped && ($0.itemID == 2301 ? position == .armor : position == .right_hand) }
        let id = owned?.itemID ?? starter?.itemID
        let key = owned.map { "gear:\($0.id)" } ?? starter.map { "starter:\($0.id)" }
        return Button { if let key { selection = key } } label: {
            HStack(spacing: 3) {
                if let id { CompanionEquipmentIcon(itemID: id).frame(width: 23, height: 23) }
                Text(id.map(itemName) ?? label).font(.game(size: 10)).lineLimit(2)
                Spacer(minLength: 0)
            }.padding(.horizontal, 3).frame(height: 28).background(key == selection ? Color.blue.opacity(0.15) : Color.white)
                .border(Color.gameBoxBorder.opacity(0.5))
        }.buttonStyle(.plain).disabled(key == nil).accessibilityIdentifier("slot-\(position.rawValue)").accessibilityLabel(label + " " + (id.map(itemName) ?? "empty"))
    }

    private func itemGrid<Cells: View>(@ViewBuilder _ cells: () -> Cells) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 1)], alignment: .leading, spacing: 1) { cells() }.padding(3)
    }

    private func itemCell(_ key: String, _ id: UInt32, quantity: String) -> some View {
        Button { selection = key } label: {
            VStack(spacing: 1) {
                ZStack(alignment: .bottomTrailing) {
                    CompanionEquipmentIcon(itemID: id).frame(width: 28, height: 28)
                    if !quantity.isEmpty { Text(quantity).font(.game(size: 9, weight: .bold)).background(Color.white.opacity(0.88)) }
                }
                Text(itemName(id)).font(.game(size: 9)).lineLimit(1)
            }.frame(maxWidth: .infinity).frame(height: 45)
                .background(selection == key ? Color.blue.opacity(0.15) : Color.white)
                .border(Color.gameBoxBorder.opacity(0.6)).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(key)
    }

    private func fetchPolicy() {
        needsPolicy = false
        send("config \(profileID)")
    }
    private func refresh() {
        if let action = state.detailRefreshAction(for: profileID) { session.companionCommand(action) }
    }
    private func send(_ action: String) { session.companionCommand(action) }
    private func empty(_ text: String) -> some View { Text(text).font(.game(size: 11)).padding(12).frame(maxWidth: .infinity) }
    private func tabButton(_ title: String, index: Int) -> some View {
        Button { tab = index } label: {
            Text(title).font(.game(size: 11, weight: tab == index ? .bold : .regular))
                .frame(maxWidth: .infinity).frame(height: 26).background(tab == index ? Color.white : Color(white: 0.9))
                .overlay { Rectangle().strokeBorder(Color.gameBoxBorder).allowsHitTesting(false) }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func control(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.game).frame(width: title == "+" || title == "−" ? 32 : 68, height: 30).disabled(disabled)
    }
}

private struct CompanionMannequin: View {
    let job: UInt32
    @Environment(GameContext.self) private var context
    @State private var animation: SpriteAnimation?
    var body: some View {
        ZStack {
            GameStripeView()
            if let frame = animation?.firstFrame {
                Image(decorative: frame, scale: 2)
            } else {
                GameImage("renewalparty/icon_jobs_\(job).bmp")
            }
        }.task(id: job) {
            animation = nil
            var character = CharacterInfo()
            character.job = Int(job)
            character.head = 1
            character.sex = 1
            guard let sprite = try? await ComposedSprite(configuration: .init(character: character), resourceManager: context.resourceManager) else { return }
            let result = await SpriteAnimationRenderer().render(composedSprite: sprite, actionType: .idle, direction: .south, rendersShadow: true)
            if !Task.isCancelled { animation = result }
        }
    }
}

private struct CompanionSkillIcon: View {
    let id: UInt32
    @Environment(GameContext.self) private var context
    @State private var resource: Resources.Image?
    var body: some View {
        ZStack {
            if let resource { Image(decorative: resource.cgImage, scale: 1).resizable().scaledToFit() }
        }.task(id: id) {
            guard let skill = SkillID(rawValue: Int(id)) else { return }
            resource = try? await context.resourceManager.image(at: .generateSkillIconImagePath(skillAegisName: skill.stringValue), removesMagentaPixels: true)
        }
    }
}

private struct CompanionEquipmentIcon: View {
    let itemID: UInt32
    @Environment(GameContext.self) private var context
    @State private var resource: Resources.Image?
    var body: some View {
        Group {
            if let resource { Image(decorative: resource.cgImage, scale: 1).resizable().scaledToFit() }
            else { Image(systemName: "shippingbox").accessibilityHidden(true) }
        }.task(id: itemID) { resource = try? await context.resourceManager.itemIconImage(forItemID: Int(itemID)) }
    }
}
