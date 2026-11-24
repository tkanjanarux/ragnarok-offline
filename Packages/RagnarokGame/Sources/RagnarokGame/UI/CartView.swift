import RagnarokModels
import SwiftUI

struct CartView: View {
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var fromInventory = false
    @State private var selected: InventoryItem?
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: "Cart", width: min(430, bounds.size.width - 24),
                             height: min(480, bounds.size.height - 24), onClose: { session.cart.visible = false }) {
                VStack(spacing: 8) {
                    if !session.cart.available { Text("You do not have an active cart.") }
                    else {
                        Text("Items \(session.cart.count)/\(session.cart.capacity) · Weight \(session.cart.weight / 10)/\(session.cart.maximumWeight / 10)").monospacedDigit()
                        Picker("Container", selection: $fromInventory) {
                            Text("Cart → Inventory").tag(false)
                            Text("Inventory → Cart").tag(true)
                        }.pickerStyle(.segmented)
                        ScrollView {
                            LazyVStack {
                                ForEach(items, id: \.index) { item in
                                    Button { selected = item } label: {
                                        HStack {
                                            InventoryItemView(item: item)
                                            Text(item.isIdentified ? context.itemInfoTable.localizedIdentifiedItemName(forItemID: item.itemID) ?? "Item \(item.itemID)" : "Unidentified item")
                                            Spacer()
                                            Text("×\(item.amount)")
                                        }.frame(minHeight: 44).contentShape(Rectangle())
                                    }.buttonStyle(.plain).disabled(item.isEquipped || session.cart.pending != nil)
                                    Divider()
                                }
                            }
                        }
                    }
                    if let message = session.cart.message { Text(message) }
                }.font(.game(size: 13)).padding(10)
            }
            .overlay {
                if let item = selected {
                    GameNumberInputBox("Amount", bounds: 1...max(1, item.amount)) { amount in
                        session.moveCartItem(index: item.index, amount: amount, toCart: fromInventory)
                        selected = nil
                    } onClose: { selected = nil }
                }
            }
        }.onChange(of: fromInventory) { _, _ in selected = nil }
    }
    private var items: [InventoryItem] {
        Array((fromInventory ? session.inventory : session.cart.inventory).items.values).sorted()
    }
}
