import SwiftUI
import RagnarokModels

struct BuyingStoreView: View {
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var name = ""
    @State private var budget = ""
    @State private var amount = "1"
    @State private var price = ""
    @State private var item: InventoryItem?
    @State private var confirmation = ""
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: "Buying stores", width: min(500,bounds.size.width - 24), height: min(640,bounds.size.height - 24), onClose: { session.closeBuyingWindow() }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let own = session.buyingStore.own, session.buyingStore.active {
                            Text("Your buying store is open. Budget: \(own.zenyLimit) Zeny")
                            ForEach(own.items, id: \.itemId) { row in Text("\(itemName(row.itemId)) ×\(row.amount) · \(row.price) Zeny each") }
                            Button("Close store") { confirmation = "close" }.frame(minHeight: 44)
                        } else if session.buyingStore.slots > 0 { prepare.disabled(session.buyingStore.waiting != nil) }
                        else if let shop = session.buyingStore.shop {
                            Text(session.buyingStore.boards[shop.AID] ?? "Buying store")
                            Text("Budget: \(shop.zenyLimit) Zeny")
                            ForEach(shop.items, id: \.itemId) { row in
                                Text("Buying \(itemName(row.itemId)) ×\(row.amount) · \(row.price) Zeny each")
                                ForEach(session.inventory.items.values.filter { $0.itemID == Int(row.itemId) && !$0.isEquipped }.sorted(), id: \.index) { inventoryItem in
                                    Button { item = inventoryItem; amount = "1" } label: {
                                        HStack { InventoryItemView(item: inventoryItem); Text("Choose stack ×\(inventoryItem.amount)") }.frame(minHeight: 44)
                                    }.disabled(session.buyingStore.waiting != nil)
                                }
                            }
                            if let item {
                                TextField("Amount",text: $amount).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                                Button("Sell \(itemName(UInt32(item.itemID)))") { confirmation = "sell" }.frame(minHeight: 44).disabled(session.buyingStore.waiting != nil)
                            }
                            Button("Back") { if session.buyingStore.waiting == nil { session.buyingStore.shop = nil } }.frame(minHeight: 44)
                        } else {
                            ForEach(session.buyingStore.boards.keys.sorted(),id: \.self) { id in
                                Button(session.buyingStore.boards[id] ?? "Store") { session.browseBuyingStore(id) }.frame(minHeight: 44)
                            }
                            if session.buyingStore.boards.isEmpty { Text("No buying stores nearby.") }
                            Text("Use the buying-store skill or permit to prepare your own store. Keep a sample of each requested item in your inventory.")
                        }
                        if let message = session.buyingStore.message { Text(message) }
                    }.padding(12).font(.game(size: 13)).buttonStyle(.game)
                }
            }
        }
        .confirmationDialog(confirmationTitle,isPresented: Binding(get: { !confirmation.isEmpty },set: { if !$0 { confirmation = "" } })) {
            Button("Confirm") {
                if confirmation == "open", let limit = UInt32(budget) { session.createBuyingStore(name: name,budget: limit) }
                else if confirmation == "close" { session.endBuyingStore() }
                else if let item, let amount = Int(amount) { session.sellToBuyingStore(index: item.index,amount: amount) }
                confirmation = ""
            }
            Button("Cancel",role: .cancel) { confirmation = "" }
        }
    }
    private var confirmationTitle: String {
        if confirmation == "close" { return "Close your buying store?" }
        if confirmation == "open" { return "Open this buying store with a budget of \(budget) Zeny?" }
        if let item, let count = UInt16(amount), let row = session.buyingStore.shop?.items.first(where: { Int($0.itemId) == item.itemID }) {
            return "Sell \(itemName(row.itemId)) ×\(count) for \(UInt64(count) * UInt64(row.price)) Zeny?"
        }
        return "Review the item and amount."
    }
    private func itemName(_ id: UInt32) -> String { context.itemInfoTable.localizedIdentifiedItemName(forItemID: Int(id)) ?? "Item \(id)" }
    @ViewBuilder private var prepare: some View {
        TextField("Shop sign",text: $name).textFieldStyle(.roundedBorder)
        TextField("Zeny budget",text: $budget).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
        ForEach(session.buyingStore.draft.values.sorted { $0.itemId < $1.itemId },id: \.itemId) { row in
            HStack {
                Text("\(itemName(row.itemId)) ×\(row.amount) · \(row.price) Zeny each")
                Button("Remove") { session.buyingStore.draft.removeValue(forKey: row.itemId) }
            }.frame(minHeight: 44)
        }
        DisclosureGroup("Choose an inventory sample") {
            ForEach(session.inventory.items.values.sorted(),id: \.index) { entry in
                Button(itemName(UInt32(entry.itemID))) { item = entry; amount = "1"; price = "" }.frame(minHeight: 44)
            }
        }
        if let item {
            Text(itemName(UInt32(item.itemID)))
            TextField("Amount to buy",text: $amount).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
            TextField("Price per item",text: $price).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
            Button("Add request") { if let count = Int(amount), let value = UInt32(price) { session.addBuyingDraft(itemID: item.itemID,amount: count,price: value) } }.frame(minHeight: 44)
        }
        Button("Open store") { confirmation = "open" }.frame(minHeight: 44).disabled(session.buyingStore.draft.isEmpty || name.isEmpty)
    }
}
