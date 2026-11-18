import SwiftUI

struct CashShopView: View {
    var close: () -> Void
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var tab: UInt16 = 6
    @State private var quantity = 1
    @State private var selectedID: String?
    @State private var useKafra = false

    private var selected: CashShopProduct? {
        session.cashShop.products.first { $0.id == selectedID && $0.tab == tab }
    }
    private var total: UInt64 { UInt64(selected?.price ?? 0) * UInt64(quantity) }
    private var canBuy: Bool {
        guard let selected else { return false }
        return session.cashShop.purchase(selected, quantity: quantity, useKafra: useKafra) != nil
    }
    private func name(_ product: CashShopProduct) -> String {
        context.itemInfoTable.localizedIdentifiedItemName(forItemID: Int(product.itemID)) ?? "Item #\(product.itemID)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cash Shop").font(.headline)
                Spacer()
                Button("Close", action: close)
            }
            Text("Cash: \(session.cashShop.cash)   Kafra: \(session.cashShop.kafra)")
                .monospacedDigit()
            Picker("Category", selection: $tab) {
                ForEach(0..<CashShopState.tabs.count, id: \.self) { i in
                    Text(CashShopState.tabs[i]).tag(UInt16(i))
                }
            }
            .pickerStyle(.menu)
            ScrollView {
                if !session.cashShop.ready {
                    Text("Opening shop… If it stays here, close and try outside this map or NPC dialog.")
                        .font(.caption)
                }
                let products = session.cashShop.products.filter { $0.tab == tab }.sorted { $0.itemID < $1.itemID }
                if products.isEmpty && session.cashShop.ready {
                    Text("No items received in this category.").font(.caption)
                }
                ForEach(products) { product in
                    Button {
                        selectedID = product.id
                        quantity = 1
                    } label: {
                        HStack {
                            Text(name(product)).multilineTextAlignment(.leading)
                            Spacer()
                            Text("\(product.price) CP")
                            if selectedID == product.id { Image(systemName: "checkmark.circle.fill") }
                        }
                        .padding(8)
                        .background(selectedID == product.id ? Color.accentColor.opacity(0.18) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(session.cashShop.pending)
                }
            }
            if let selected {
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                    .disabled(session.cashShop.pending)
                Toggle("Use Kafra Points first", isOn: $useKafra)
                    .disabled(session.cashShop.pending)
                HStack {
                    Text("Total: \(total) points").monospacedDigit()
                    Spacer()
                    Button(session.cashShop.pending ? "Buying…" : "Buy") {
                        session.buyCashShop(selected, quantity: quantity, useKafra: useKafra)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canBuy)
                }
                if !canBuy && !session.cashShop.pending && session.cashShop.ready {
                    Text("Not enough points.").font(.caption)
                }
            }
            if let message = session.cashShop.message {
                Text(message).font(.caption)
            }
        }
        .padding()
        .frame(maxWidth: 440, maxHeight: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
        .onAppear { session.openCashShop() }
        .onDisappear { session.closeCashShop() }
        .onChange(of: tab) { selectedID = nil; quantity = 1 }
    }
}
