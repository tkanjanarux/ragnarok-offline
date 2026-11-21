import RagnarokResources
import SwiftUI

/// Original game skin, bounded controls and server-authoritative companion details.
struct CompanionEquipmentView: View {
    let profileID: UInt32
    var close: () -> Void
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
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
        ClassicGamePanel(title: "Companion Details", width: 360, height: 470, onClose: close) {
            VStack(spacing: 5) {
                HStack {
                    Text(verbatim: profile?.name ?? "Companion").font(.game(weight: .bold))
                    Spacer()
                    Text("Base \(profile?.level ?? 0) / Job \(profile?.jobLevel ?? 0)").font(.game(size: 10))
                }.frame(height: 24)
                Text(verbatim: state.detailReady ? state.activity : "Refresh to inspect companion.")
                    .font(.game(size: 10)).frame(maxWidth: .infinity, alignment: .leading).frame(height: 28)
                HStack(spacing: 2) {
                    tabButton("Gear", index: 0); tabButton("Skills", index: 1)
                    tabButton("Supplies", index: 2); tabButton("Your Bag", index: 3)
                }.frame(height: 28)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if state.equipmentProfile == profileID && (state.detailReady || (state.pending && state.action == "inspect \(profileID)")) {
                            switch tab {
                            case 0:
                                VStack(spacing: 0) {
                                    ForEach(state.gearRows) { row in
                                        itemRow(key: row.id, itemID: row.itemID, detail: row.detail, details: row.details)
                                    }
                                }
                            case 1:
                                ForEach(state.skills) { skill in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack { Text(skill.name).font(.game(weight: .bold)); Spacer(); Text("Lv \(skill.level)/\(skill.maximum)").font(.game(size: 11)) }
                                        HStack {
                                            Text("\(skill.status) · SP \(skill.sp)").font(.game(size: 10))
                                            Spacer()
                                            if let key = skill.policyKey, let order = allowedSkills {
                                                Button(order.contains(key) ? "AI: On" : "AI: Off") {
                                                    let updated = order.contains(key) ? order.filter { $0 != key } : order + [key]
                                                    send("skills \(profileID) \(updated.isEmpty ? "none" : updated.joined(separator: ","))")
                                                }.buttonStyle(.game).disabled(!ready)
                                            }
                                        }
                                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color.white)
                                    Divider()
                                }
                            case 2:
                                ForEach(state.supplies) { item in itemRow(key: "supply:\(item.id)", itemID: item.itemID, detail: "Remaining: \(item.amount)") }
                                if state.supplies.isEmpty { empty(state.suppliesAvailable ? "No supplies. Reserve, then give potions or syrups from Your Bag." : "Supplies are not enabled on this server.") }
                            default:
                                ForEach(state.supplyBag) { item in itemRow(key: "supplybag:\(item.id):\(item.itemID)", itemID: item.itemID, detail: "Supply · Available: \(item.amount)") }
                                ForEach(state.bag) { item in itemRow(key: "bag:\(item.id):\(item.uniqueID)", itemID: item.itemID, detail: "Equipment · Available to give", details: item.details) }
                                if state.bag.isEmpty && state.supplyBag.isEmpty { empty("No eligible items. Transferable equipment and supported potions or syrups only.") }
                            }
                        } else { empty(state.pending ? "Loading…" : "Waiting to refresh companion details.") }
                    }
                }.frame(height: 178).overlay { Rectangle().strokeBorder(Color.gameBoxBorder).allowsHitTesting(false) }
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
                        control(tab == 2 ? "Return" : "Give", disabled: !ready || profile?.active != false || (tab == 2 ? supply == nil : bagItem == nil && supplyBag == nil)) {
                            if tab == 2, let supply { send("supplytake \(profileID) 0:\(supply.itemID):0:\(amount)") }
                            else if let item = supplyBag { send("supplygive \(profileID) \(item.id):\(item.itemID):\(item.amount):\(amount)") }
                            else if let item = bagItem { send("giveui \(profileID) \(item.id):\(item.uniqueID)") }
                        }
                    } else { Text("Skill levels follow Job. Blue Gemstone: \(profile?.gems ?? 0)").font(.game(size: 10)) }
                }.frame(height: 34)
                HStack(spacing: 5) {
                    control(profile?.active == true ? "Reserve" : "Summon", disabled: !ready || profile == nil) { send("\(profile?.active == true ? "bench" : "summon") \(profileID)") }
                    control("Stop", disabled: !ready || profile?.active != true || profile?.mode == 3) { send("stop \(profileID)") }
                    control("Refresh", disabled: state.pending) { refresh() }
                }.frame(height: 34)
                Text(tab == 1 ? "Tap AI: On or Off to choose which learned skills your companion may use." : tab == 2 || tab == 3 ? supplyHint : gearHint)
                    .font(.game(size: 10)).frame(height: 32)
                Text(verbatim: feedback).font(.game(size: 10)).frame(maxWidth: .infinity, alignment: .leading).frame(height: 38)
            }.padding(.horizontal, 8)
        }
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
    private var supplyHint: String {
        let rule = state.equipmentProfile == profileID ? state.potionRule : nil
        return [rule, "One potion every 2s. Stop pauses use. Reserve to transfer up to 100."].compactMap { $0 }.joined(separator: " ")
    }
    private var gearHint: String {
        if selection.hasPrefix("starter:") { return "Starter gear is managed automatically. Select your own equipment to equip or return it." }
        guard let gear else { return "Select a piece of your equipment to see the available actions." }
        if gear.returning { return "Returning this item to your bag…" }
        if profile?.active == false { return "Return this item to your bag, or Summon and then Stop to change equipment." }
        if profile?.mode == 3 { return "Change the selected equipment here. Choose Reserve to return it to your bag." }
        return "Choose Stop to change equipment, or Reserve to return it to your bag."
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
        Button(title, action: action).buttonStyle(.game).frame(width: title == "+" || title == "−" ? 36 : 96, height: 30).disabled(disabled)
    }
    private func itemRow(key: String, itemID: UInt32, detail: String, details: CompanionItemDetails = .plain) -> some View {
        let name = context.itemInfoTable.localizedIdentifiedItemName(forItemID: Int(itemID))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemName = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Item #\(itemID)"
        let cardNames = details.cards.map { context.itemInfoTable.localizedIdentifiedItemName(forItemID: Int($0)) ?? "#\($0)" }
        return Button { selection = key } label: {
            HStack(spacing: 8) {
                CompanionEquipmentIcon(itemID: itemID).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: details.refine > 0 ? "+\(details.refine) \(itemName)" : itemName).font(.game(size: 12)).lineLimit(1)
                    Text(detail).font(.game(size: 10))
                    if !cardNames.isEmpty { Text(verbatim: cardNames.joined(separator: ", ")).font(.game(size: 10)) }
                }; Spacer()
            }.padding(.horizontal, 6).frame(minHeight: 44).foregroundStyle(Color.gameLabel)
                .background(selection == key ? Color(red: 0.82, green: 0.89, blue: 1) : Color.white).contentShape(Rectangle())
        }.buttonStyle(.plain)
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
