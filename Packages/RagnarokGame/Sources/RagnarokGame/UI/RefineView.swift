import SwiftUI

struct RefineView: View {
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var blessing = false
    @State private var confirming: UInt32?
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: "Refining", width: min(460, bounds.size.width - 24),
                             height: min(540, bounds.size.height - 24), onClose: session.closeRefine) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose equipment").fontWeight(.bold)
                        ForEach(session.inventory.equipItems.filter { $0.isIdentified && !$0.isDamaged && ($0.type == .weapon || $0.type == .armor) }, id: \.index) { item in
                            Button { session.selectRefineItem(item.index) } label: {
                                HStack {
                                    InventoryItemView(item: item)
                                    Text("+\(item.refineLevel) \(name(item.itemID))")
                                    Spacer()
                                    if session.refine.selectedIndex == item.index { Image(systemName: "checkmark") }
                                }.frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(session.refine.pending != nil)
                        }
                        Divider()
                        if let message = session.refine.message { Text(message) }
                        if session.refine.blessingCount > 0 {
                            Toggle("Blacksmith Blessing ×\(session.refine.blessingCount)", isOn: $blessing)
                                .disabled(session.refine.pending != nil)
                        }
                        ForEach(session.refine.materials) { material in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(name(Int(material.id))) · \(material.chance)% · \(material.zeny) Zeny")
                                Button("Refine") { confirming = material.id }
                                    .buttonStyle(.game).frame(minHeight: 44)
                                    .disabled(session.refine.pending != nil || !canPay(material))
                            }
                        }
                        Text("Failure may destroy or downgrade the item. Materials and Zeny are consumed.").foregroundStyle(.secondary)
                    }.font(.game(size: 13)).padding(10)
                }
            }
        }
        .confirmationDialog("Refine this item using the selected materials and Zeny?", isPresented: Binding(
            get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Refine") {
                if let material = confirming { session.requestRefine(material: material, blessing: blessing && session.refine.blessingCount > 0) }
                confirming = nil
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        }
    }
    private func name(_ id: Int) -> String { context.itemInfoTable.localizedIdentifiedItemName(forItemID: id) ?? "Item \(id)" }
    private func canPay(_ material: RefineState.Material) -> Bool {
        session.playerStatus.zeny >= material.zeny && session.inventory.items.values.contains { $0.itemID == Int(material.id) && $0.amount > 0 }
            && (!blessing || session.refine.blessingCount == 0 || session.inventory.items.values.contains { $0.itemID == 6635 && $0.amount >= session.refine.blessingCount })
    }
}
