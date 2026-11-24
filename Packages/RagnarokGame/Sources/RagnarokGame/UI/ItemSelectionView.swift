import RagnarokModels
import SwiftUI

struct ItemSelectionView: View {
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var confirmingCardTarget: Int?

    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: title, width: min(420, bounds.size.width - 24),
                             height: min(420, bounds.size.height - 24), onClose: session.closeItemSelection) {
                VStack(spacing: 8) {
                    if let message = session.itemSelection.message { Text(message).font(.game(size: 13)) }
                    if session.itemSelection.selection?.kind == .produce {
                        Text("Optional forging materials").font(.game(size: 12))
                        ForEach(0..<3, id: \.self) { slot in
                            Picker("Slot \(slot + 1)", selection: Binding(get: { session.itemSelection.extraMaterials[slot] }, set: { session.itemSelection.extraMaterials[slot] = $0 })) {
                                Text("None").tag(UInt32(0))
                                ForEach([994, 995, 996, 997, 1000].filter { id in session.inventory.items.values.contains { $0.itemID == id && $0.amount > 0 } }, id: \.self) { id in
                                    Text(context.itemInfoTable.localizedIdentifiedItemName(forItemID: id) ?? "Item \(id)").tag(UInt32(id))
                                }
                            }.disabled(session.itemSelection.pending != nil)
                        }
                    }
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(session.itemSelection.selection?.values ?? [], id: \.self) { value in
                                if session.itemSelection.selection?.kind == .skill {
                                    Button(context.skillInfoTable.localizedSkillName(forSkillID: value) ?? "Skill \(value)") { session.chooseItemSelection(value) }.frame(minHeight: 44)
                                } else if let item = displayItem(value) {
                                    Button {
                                        if session.itemSelection.selection?.kind == .card { confirmingCardTarget = value }
                                        else { session.chooseItemSelection(value) }
                                    } label: {
                                        HStack {
                                            InventoryItemView(item: item, showsAmount: false)
                                            Text(name(item)).multilineTextAlignment(.leading)
                                            Spacer()
                                            if session.itemSelection.selection?.kind == .identify || session.itemSelection.selection?.kind == .card { Text("#\(value)").foregroundStyle(.secondary) }
                                        }.frame(minHeight: 44).contentShape(Rectangle())
                                    }.buttonStyle(.plain).disabled(session.itemSelection.pending != nil)
                                    Divider()
                                }
                            }
                        }
                    }
                    Button("Close", action: session.closeItemSelection).buttonStyle(.game).frame(minHeight: 44)
                }.font(.game(size: 13)).padding(10)
            }
        }
        .confirmationDialog("Insert this card permanently?", isPresented: Binding(
            get: { confirmingCardTarget != nil }, set: { if !$0 { confirmingCardTarget = nil } })) {
            Button("Insert card") {
                if let index = confirmingCardTarget { session.chooseItemSelection(index) }
                confirmingCardTarget = nil
            }
            Button("Cancel", role: .cancel) { confirmingCardTarget = nil }
        }
    }

    private var title: String {
        switch session.itemSelection.selection?.kind {
        case .identify: "Identify item"
        case .card: "Insert card"
        case .arrow: "Select material"
        case .produce: "Produce item"
        case .cooking: "Create item"
        case .skill: "Select skill"
        case nil: "Items"
        }
    }
    private func displayItem(_ value: Int) -> InventoryItem? {
        if let kind = session.itemSelection.selection?.kind, [.arrow, .produce, .cooking].contains(kind) {
            if let item = session.inventory.items.values.first(where: { $0.itemID == value }) { return item }
            var item = InventoryItem(); item.itemID = value; item.isIdentified = true
            return item // catalogue entry supplied by server, never inserted into inventory
        }
        return session.inventory.items[value]
    }
    private func name(_ item: InventoryItem) -> String {
        item.isIdentified ? (context.itemInfoTable.localizedIdentifiedItemName(forItemID: item.itemID) ?? "Item \(item.itemID)") : "Unidentified item"
    }
}
