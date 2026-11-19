import RagnarokResources
import SwiftUI

/// Classic storage-style list and game-skin buttons; all mutations stay server-authoritative.
struct CompanionEquipmentView: View {
    let profileID: UInt32
    var close: () -> Void
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var bagTab = false
    @State private var selection: UInt32?
    @State private var feedback = "Loading equipment…"
    @State private var waitingForTransfer = false
    private var state: CompanionState { session.companions }
    private var profile: CompanionProfile? { state.profiles.first { $0.id == profileID } }
    private var ready: Bool { state.ready && state.available && state.equipmentReady && state.equipmentProfile == profileID && !state.pending && !state.transferPending }
    private var gear: CompanionEquipment? { state.equipment.first { $0.id == selection } }
    private var bagItem: CompanionBagItem? { state.bag.first { $0.id == selection } }
    private var stopped: Bool { profile?.mode == 3 }

    var body: some View {
        ClassicGamePanel(title: "Companion Equipment", width: 360, height: 420, onClose: close) {
            VStack(spacing: 5) {
                HStack {
                    Text(verbatim: profile?.name ?? "Companion").font(.game(weight: .bold))
                    Spacer()
                    Text(profile?.stateName ?? "Unavailable").font(.game(size: 10))
                }.frame(height: 24)
                HStack(spacing: 5) {
                    tab("Equipment (\(state.equipment.count)/8)", bag: false)
                    tab("Your Inventory", bag: true)
                }.frame(height: 30)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if state.equipmentReady && state.equipmentProfile == profileID {
                            if bagTab {
                                ForEach(state.bag) { item in itemRow(id: item.id, itemID: item.itemID, detail: "Available to give") }
                                if state.bag.isEmpty { empty("No eligible equipment. Only plain, identified, unequipped items are supported.") }
                            } else {
                                ForEach(state.equipment) { item in
                                    itemRow(id: item.id, itemID: item.itemID, detail: item.returning ? "Returning…" : item.equipped ? "Equipped" : "Stored")
                                }
                                if state.equipment.isEmpty { empty("No equipment stored. Select Your Inventory to give an item.") }
                            }
                        } else { empty(state.pending ? "Loading…" : "Equipment unavailable. Refresh to try again.") }
                    }
                }.frame(height: 170).overlay { Rectangle().strokeBorder(Color.gameBoxBorder).allowsHitTesting(false) }
                HStack(spacing: 5) {
                    if bagTab {
                        control("Give", disabled: !ready || profile?.active != false || bagItem == nil || state.equipment.count >= 8) {
                            if let item = bagItem { waitingForTransfer = true; send("giveui \(profileID) \(item.id):\(item.uniqueID)") }
                        }
                    } else {
                        control(gear?.equipped == true ? "Unequip" : "Equip", disabled: !ready || !stopped || gear == nil || gear?.returning == true) {
                            if let gear { send("\(gear.equipped ? "unequip" : "equip") \(profileID) \(gear.id)") }
                        }
                        control("Return", disabled: !ready || profile?.active != false || gear == nil || gear?.returning == true) {
                            if let gear { waitingForTransfer = true; send("take \(profileID) \(gear.id)") }
                        }
                    }
                }.frame(height: 36)
                HStack(spacing: 5) {
                    control(profile?.active == true ? "Reserve" : "Summon", disabled: !ready || profile == nil) {
                        send("\(profile?.active == true ? "bench" : "summon") \(profileID)")
                    }
                    control("Stop", disabled: !ready || profile?.active != true || stopped) { send("stop \(profileID)") }
                    control("Refresh", disabled: state.pending) { refresh() }
                }.frame(height: 36)
                Text(profile?.active == true ? "Stop to equip. Reserve to give or return items." : "Give or return items here. Summon, then Stop to equip.")
                    .font(.game(size: 10)).frame(height: 28)
                Text(verbatim: feedback).font(.game(size: 10)).frame(maxWidth: .infinity, alignment: .leading).frame(height: 42)
            }.padding(.horizontal, 8)
        }
        .onChange(of: bagTab) { selection = nil }
        .onChange(of: state.completedSequence) {
            guard !state.pending else { return }
            if state.action.hasPrefix("equipment ") {
                if waitingForTransfer || !state.equipmentReady || feedback == "Loading equipment…" { feedback = state.message }
                waitingForTransfer = state.transferPending
                if bagTab && !state.bag.contains(where: { $0.id == selection }) { selection = nil }
                if !bagTab && !state.equipment.contains(where: { $0.id == selection }) { selection = nil }
            } else {
                feedback = state.message
                if !state.message.contains("Waiting for inventory") { waitingForTransfer = false }
                if state.ready { refresh() }
            }
        }
        .task {
            // A roster refresh may already be in flight when this panel opens.
            while state.pending && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
            guard !Task.isCancelled else { return }
            refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                if !state.pending && state.ready && (state.transferPending || waitingForTransfer) { refresh() }
            }
        }
    }
    private func refresh() { session.companionCommand(state.ready ? "equipment \(profileID)" : "list") }
    private func send(_ action: String) { session.companionCommand(action) }
    private func empty(_ text: String) -> some View { Text(text).font(.game(size: 11)).padding(12).frame(maxWidth: .infinity) }
    private func tab(_ title: String, bag: Bool) -> some View {
        Button { bagTab = bag } label: {
            Text(title).font(.game(size: 11, weight: bagTab == bag ? .bold : .regular))
                .frame(maxWidth: .infinity).frame(height: 28)
                .background(bagTab == bag ? Color.white : Color(white: 0.9))
                .overlay { Rectangle().strokeBorder(Color.gameBoxBorder).allowsHitTesting(false) }
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func control(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.game).frame(width: 96, height: 32).disabled(disabled)
    }
    private func itemRow(id: UInt32, itemID: UInt32, detail: String) -> some View {
        Button { selection = id } label: {
            HStack(spacing: 8) {
                CompanionEquipmentIcon(itemID: itemID).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: context.itemInfoTable.localizedIdentifiedItemName(forItemID: Int(itemID)) ?? "Item #\(itemID)")
                        .font(.game(size: 12)).lineLimit(1)
                    Text(detail).font(.game(size: 10))
                }
                Spacer()
            }.padding(.horizontal, 6).frame(height: 44)
                .foregroundStyle(Color.gameLabel)
                .background(selection == id ? Color(red: 0.82, green: 0.89, blue: 1) : Color.white)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!ready)
    }
}

private struct CompanionEquipmentIcon: View {
    let itemID: UInt32
    @Environment(GameContext.self) private var context
    @State private var resource: Resources.Image?
    var body: some View {
        Group {
            if let resource { Image(decorative: resource.cgImage, scale: 1).resizable().scaledToFit() }
            else { Color.clear }
        }.task(id: itemID) { resource = try? await context.resourceManager.itemIconImage(forItemID: Int(itemID)) }
    }
}
