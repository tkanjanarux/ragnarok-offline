import SwiftUI
import RagnarokModels

struct VendingView: View {
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var name = ""
    @State private var selected: InventoryItem?
    @State private var amount = "1"
    @State private var price = ""
    @State private var buyingIndex: UInt16?
    @State private var confirmation = ""
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: "Player shops", width: min(520,bounds.size.width - 24), height: min(650,bounds.size.height - 24), onClose: { session.closeVending() }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if session.vending.active {
                            Text("Your shop is open.")
                            ForEach(session.vending.own, id: \.index) { item in Text("\(itemName(item.itemId)) ×\(item.amount) · \(item.price) Zeny each") }
                            Button("Close shop") { confirmation = "close" }.frame(minHeight: 44)
                        } else if session.vending.preparingSlots > 0 { prepare.disabled(session.vending.waiting != nil) }
                        else if let shop = session.vending.shop {
                            Text(session.vending.boards[shop.AID]?.name ?? "Shop")
                            ForEach(shop.items, id: \.index) { item in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(item.refine > 0 ? "+\(item.refine) " : "")\(item.identified != 0 ? itemName(item.itemId) : "Unidentified item") ×\(item.amount)")
                                    Text("\(item.price) Zeny each")
                                    if item.damaged != 0 { Text("Damaged") }
                                    ForEach(Array(item.slot.card.enumerated()), id: \.offset) { _, card in
                                        if card != 0 { Text("Card: \(itemName(card))") }
                                    }
                                    ForEach(Array(item.option_data.enumerated()), id: \.offset) { _, option in
                                        if option.index != 0 { Text("Option \(option.index): \(option.value)") }
                                    }
                                    Button("Buy") { buyingIndex = UInt16(bitPattern: item.index); amount = "1" }.frame(minHeight: 44)
                                }
                            }.disabled(session.vending.waiting != nil)
                            if buyingIndex != nil {
                                TextField("Amount", text: $amount).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                                Button("Review purchase") { confirmation = "buy" }.frame(minHeight: 44).disabled(session.vending.waiting != nil)
                            }
                            Button("Back to shops") { if session.vending.waiting == nil { session.vending.shop = nil; session.vending.browsing = nil } }.frame(minHeight: 44)
                        } else {
                            Text("Nearby shops")
                            ForEach(session.vending.boards.values.sorted { $0.id < $1.id }) { shop in
                                Button(shop.name) { session.browseVending(shop.id) }.frame(minHeight: 44).disabled(session.vending.waiting != nil)
                            }
                            if session.vending.boards.isEmpty { Text("No shops nearby.") }
                            Text("Use Vending with a cart to open your own shop.")
                        }
                        if let message = session.vending.message { Text(message) }
                    }.padding(12)
                }.font(.game(size: 13)).buttonStyle(.game)
            }
        }
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { !confirmation.isEmpty }, set: { if !$0 { confirmation = "" } })) {
            Button("Confirm") {
                if confirmation == "open" { session.openVending(name: name) }
                else if confirmation == "close" { session.endVending() }
                else if let index = buyingIndex, let amount = UInt16(amount) { session.buyVending(index: index, amount: amount) }
                confirmation = ""
            }
            Button("Cancel", role: .cancel) { confirmation = "" }
        }
    }
    private func itemName(_ id: UInt32) -> String { context.itemInfoTable.localizedIdentifiedItemName(forItemID: Int(id)) ?? "Item \(id)" }
    private var confirmationTitle: String {
        if confirmation == "open" { return "Open this shop at the listed prices?" }
        if confirmation == "close" { return "Close your shop?" }
        if let index = buyingIndex, let item = session.vending.shop?.items.first(where: { UInt16(bitPattern: $0.index) == index }), let count = UInt16(amount) {
            return "Buy \(itemName(item.itemId)) ×\(count) for \(UInt64(item.price) * UInt64(count)) Zeny?"
        }
        return "Review the purchase amount."
    }
    @ViewBuilder private var prepare: some View {
        TextField("Shop sign", text: $name).textFieldStyle(.roundedBorder)
        Text("Up to \(session.vending.preparingSlots) items")
        ForEach(session.vending.draft.values.sorted { $0.index < $1.index }, id: \.index) { row in
            HStack {
                Text("\(itemName(UInt32(session.cart.inventory.items[Int(row.index)]?.itemID ?? 0))) ×\(row.amount) · \(row.price) Zeny each")
                Spacer(); Button("Remove") { session.vending.draft.removeValue(forKey: row.index) }
            }.frame(minHeight: 44)
        }
        DisclosureGroup("Choose cart item") {
            ForEach(session.cart.inventory.items.values.sorted(), id: \.index) { item in
                Button { selected = item; amount = "1"; price = "" } label: {
                    HStack { InventoryItemView(item: item); Text(itemName(UInt32(item.itemID))); Spacer(); Text("×\(item.amount)") }.frame(minHeight: 44)
                }
            }
        }
        if let selected {
            Text(itemName(UInt32(selected.itemID)))
            TextField("Amount", text: $amount).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
            TextField("Price per item", text: $price).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
            Button("Add to shop") { if let amount = Int(amount), let price = UInt32(price) { session.addVendingDraft(index: selected.index, amount: amount, price: price) } }.frame(minHeight: 44)
        }
        Button("Open shop") { confirmation = "open" }.frame(minHeight: 44).disabled(session.vending.draft.isEmpty || name.isEmpty || session.vending.waiting != nil)
    }
}
