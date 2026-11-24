import SwiftUI

struct EquipmentSwitchView: View {
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: "Equipment switch", width: min(460, bounds.size.width - 24),
                             height: min(500, bounds.size.height - 24), onClose: { session.equipmentSwitch.visible = false }) {
                VStack {
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(session.inventory.equipItems.filter { $0.isIdentified }, id: \.index) { item in
                                HStack {
                                    InventoryItemView(item: item)
                                    Text(context.itemInfoTable.localizedIdentifiedItemName(forItemID: item.itemID) ?? "Item \(item.itemID)")
                                    Spacer()
                                    if session.equipmentSwitch.entries[item.index] != nil {
                                        Button("Remove") { session.changeSwitchEquipment(index: item.index, remove: true) }
                                    } else {
                                        Button("Add") { session.changeSwitchEquipment(index: item.index, remove: false) }
                                            .disabled(item.isEquipped || item.location.isEmpty)
                                    }
                                }.frame(minHeight: 44)
                                Divider()
                            }
                        }.disabled(session.equipmentSwitch.pending != nil)
                    }
                    if let message = session.equipmentSwitch.message { Text(message) }
                    Button("Switch equipment", action: session.requestEquipmentSwitch)
                        .disabled(session.equipmentSwitch.entries.isEmpty || session.equipmentSwitch.pending != nil)
                        .frame(minHeight: 44)
                }.buttonStyle(.game).font(.game(size: 13)).padding(10)
            }
        }
    }
}

struct EquipmentCompareView: View {
    @Environment(PlaySession.self) private var session
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: "Compare equipment", width: min(620, bounds.size.width - 24),
                             height: min(540, bounds.size.height - 24), onClose: { session.equipmentSwitch.compareIndex = nil }) {
                ScrollView {
                    if let index = session.equipmentSwitch.compareIndex, let item = session.inventory.items[index] {
                        VStack(spacing: 10) {
                            Text("Selected").fontWeight(.bold)
                            InventoryItemPreview(item: item)
                            Text("Currently equipped").fontWeight(.bold)
                            let current = session.inventory.equipItems.filter { $0.isEquipped && !$0.equippedLocation.intersection(item.location).isEmpty }
                            if current.isEmpty { Text("No item equipped in these slots.") }
                            ForEach(current, id: \.index) { InventoryItemPreview(item: $0) }
                        }.font(.game(size: 13)).frame(maxWidth: .infinity).padding(10)
                    }
                }
            }
        }
    }
}
