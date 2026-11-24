import RagnarokModels
import SwiftUI

struct TradeView: View {
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var zeny = "0"
    @State private var selected: InventoryItem?
    @State private var confirming = false
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: "Trade — \(session.trade.partnerName)", width: min(500, bounds.size.width - 24), height: min(600, bounds.size.height - 24), onClose: { session.cancelTrade() }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if session.trade.invitation {
                            Text("Trade request from \(session.trade.partnerName)")
                            HStack {
                                Button("Accept") { session.replyToTrade(accept: true) }
                                Button("Decline") { session.replyToTrade(accept: false) }
                            }.frame(minHeight: 44)
                        } else if session.trade.active {
                            Text("You offer").fontWeight(.bold)
                            ForEach(session.trade.mine.values.sorted(), id: \.index) { item in row(item) }
                            if !session.trade.locked {
                                TextField("Zeny", text: $zeny).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                                DisclosureGroup("Add inventory item") {
                                    ForEach(session.inventory.items.values.sorted(), id: \.index) { item in
                                        Button { selected = item } label: { row(item) }
                                            .disabled(item.isEquipped || session.trade.waiting != nil)
                                    }
                                }
                                Button("Lock offer") { session.lockTrade(zeny: Int32(zeny) ?? -1) }
                                    .disabled(session.trade.waiting != nil).frame(minHeight: 44)
                            } else { Text("\(session.trade.offeredZeny) Zeny · Locked") }
                            Divider()
                            Text("You receive").fontWeight(.bold)
                            ForEach(session.trade.theirs) { offer in row(offer.item) }
                            Text("\(session.trade.receivedZeny) Zeny")
                            Text(session.trade.otherLocked ? "Other player locked their offer." : "Other player is choosing items…")
                            Button("Complete trade") { confirming = true }
                                .disabled(!session.trade.locked || !session.trade.otherLocked || session.trade.waiting != nil).frame(minHeight: 44)
                            Button("Cancel trade") { session.cancelTrade() }.frame(minHeight: 44)
                        }
                        if let message = session.trade.message { Text(message) }
                    }.padding(12)
                }.font(.game(size: 13)).buttonStyle(.game)
            }
            .overlay {
                if let item = selected {
                    GameNumberInputBox("Amount", bounds: 1...max(1, min(item.amount, Int(Int16.max)))) { amount in
                        session.addTradeItem(index: item.index, amount: amount); selected = nil
                    } onClose: { selected = nil }
                }
            }
        }
        .confirmationDialog("Exchange the locked items and Zeny?", isPresented: $confirming) {
            Button("Complete trade") { session.commitTrade() }
            Button("Cancel", role: .cancel) { }
        }
    }
    private func row(_ item: InventoryItem) -> some View {
        HStack {
            InventoryItemView(item: item)
            VStack(alignment: .leading, spacing: 3) {
            Text(item.isIdentified ? (item.refineLevel > 0 ? "+\(item.refineLevel) " : "") + (context.itemInfoTable.localizedIdentifiedItemName(forItemID: item.itemID) ?? "Item \(item.itemID)") : "Unidentified item")
            ForEach(Array(item.slots.enumerated()), id: \.offset) { slot in
                if slot.element != 0 { Text("Slot \(slot.offset + 1): \(context.itemInfoTable.localizedIdentifiedItemName(forItemID: slot.element) ?? String(slot.element))") }
            }
            if let grade = item.enchantGrade, grade > 0 { Text("Grade \(grade)") }
            ForEach(Array(item.randomOptions.enumerated()), id: \.offset) { option in
                Text("Option \(option.element.id): \(option.element.value) (\(option.element.parameter))")
            }
            }
            Spacer(); Text("×\(item.amount)")
        }.frame(minHeight: 44)
    }
}
