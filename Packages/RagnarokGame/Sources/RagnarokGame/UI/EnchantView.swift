import SwiftUI

struct EnchantView: View {
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var confirming: EnchantState.Action?
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: "Enchant", width: min(480, bounds.size.width - 24), height: min(580, bounds.size.height - 24), onClose: session.closeEnchant) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let message = session.enchant.message { Text(message) }
                        if let recipe = session.enchant.recipe {
                            Text("Choose unequipped equipment").fontWeight(.bold)
                            ForEach(session.inventory.equipItems.filter { recipe.targets.contains($0.itemID) }, id: \.index) { item in
                                Button {
                                    session.enchant.selected = item.index
                                } label: {
                                    HStack {
                                        InventoryItemView(item: item)
                                        Text("+\(item.refineLevel) \(name(item.itemID))")
                                        Spacer()
                                        if session.enchant.selected == item.index { Image(systemName: "checkmark") }
                                    }.frame(minHeight: 44)
                                }.disabled(session.enchant.pending != nil)
                            }
                            if let index = session.enchant.selected, let item = session.inventory.items[index] {
                                ForEach(Array(item.slots.enumerated()), id: \.offset) { entry in
                                    if entry.element != 0 { Text("Slot \(entry.offset + 1): \(name(entry.element))") }
                                }
                                let actions = session.enchant.actions(for: item, registered: session.equipmentSwitch.entries[index] != nil)
                                if actions.isEmpty { Text("No available enchant. Check the item's refine level, grade, slots and equipment switch registration.") }
                                ForEach(actions) { action in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(title(action)) · \(action.price) Zeny")
                                        ForEach(Array(action.materials.enumerated()), id: \.offset) { entry in
                                            Text("\(name(entry.element.id)) ×\(entry.element.amount)")
                                        }
                                        Button(title(action)) { confirming = action }
                                            .frame(minHeight: 44).disabled(session.enchant.pending != nil || !canPay(action))
                                    }
                                }
                                Text("Enchanting or resetting may fail. Materials and Zeny are consumed when the attempt is processed.").foregroundStyle(.secondary)
                            }
                        }
                    }.padding(12)
                }.font(.game(size: 13)).buttonStyle(.game)
            }
        }
        .confirmationDialog("Use the listed materials and Zeny?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Confirm") { if let action = confirming { session.requestEnchant(action) }; confirming = nil }
            Button("Cancel", role: .cancel) { confirming = nil }
        }
    }
    private func name(_ id: Int) -> String { context.itemInfoTable.localizedIdentifiedItemName(forItemID: id) ?? "Item \(id)" }
    private func title(_ action: EnchantState.Action) -> String {
        switch action.kind {
        case .random: "Random enchant · Slot \(action.slot + 1)"
        case .perfect: "Enchant: \(name(action.item))"
        case .upgrade: "Upgrade: \(name(action.result))"
        case .reset: "Reset enchants"
        }
    }
    private func canPay(_ action: EnchantState.Action) -> Bool {
        session.playerStatus.zeny >= action.price && action.materials.allSatisfy { cost in
            session.inventory.items.values.contains { $0.itemID == cost.id && $0.amount >= cost.amount }
        }
    }
}
