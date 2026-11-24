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
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(session.itemSelection.selection?.values ?? [], id: \.self) { value in
                                if let item = displayItem(value) {
                                    Button {
                                        if session.itemSelection.selection?.kind == .card { confirmingCardTarget = value }
                                        else { session.chooseItemSelection(value) }
                                    } label: {
                                        HStack {
                                            InventoryItemView(item: item)
                                            Text(name(item)).multilineTextAlignment(.leading)
                                            Spacer()
                                            if session.itemSelection.selection?.kind != .arrow { Text("#\(value)").foregroundStyle(.secondary) }
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
        case nil: "Items"
        }
    }
    private func displayItem(_ value: Int) -> InventoryItem? {
        if session.itemSelection.selection?.kind == .arrow {
            return session.inventory.items.values.first { $0.itemID == value }
        }
        return session.inventory.items[value]
    }
    private func name(_ item: InventoryItem) -> String {
        item.isIdentified ? (context.itemInfoTable.localizedIdentifiedItemName(forItemID: item.itemID) ?? "Item \(item.itemID)") : "Unidentified item"
    }
}
