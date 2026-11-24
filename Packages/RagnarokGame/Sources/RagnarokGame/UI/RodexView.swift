import SwiftUI
import RagnarokModels

struct RodexView: View {
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var receiver = ""
    @State private var title = ""
    @State private var text = ""
    @State private var zeny = "0"
    @State private var selected: InventoryItem?
    @State private var confirmation = ""
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: "RODEX", width: min(520, bounds.size.width - 24), height: min(650, bounds.size.height - 24), onClose: { session.closeRodex() }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if session.rodex.writing { compose.disabled(session.rodex.pending != nil) }
                        else {
                            HStack {
                                Button("Refresh") { session.openRodex() }
                                Button("Write") { session.beginRodex() }
                            }.frame(minHeight: 44).disabled(session.rodex.pending != nil)
                            if session.rodex.entries.isEmpty && session.rodex.pending == nil { Text("No mail.") }
                            ForEach(session.rodex.entries, id: \.id) { entry in
                                Button { session.readRodex(entry) } label: {
                                    VStack(alignment: .leading) {
                                        Text(entry.title).fontWeight(entry.read ? .regular : .bold)
                                        Text("From: \(entry.sender)")
                                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }.disabled(session.rodex.pending != nil)
                            }
                            if let letter = session.rodex.letter {
                                Divider(); Text(letter.text)
                                Text("\(letter.zeny) Zeny")
                                ForEach(Array(letter.items.enumerated()), id: \.offset) { _, item in
                                    Text("\(item.refiningLevel > 0 ? "+\(item.refiningLevel) " : "")\(itemName(item.ITID)) ×\(item.count)")
                                }
                                HStack {
                                    Button("Receive Zeny") { confirmation = "zeny" }.disabled(letter.zeny == 0)
                                    Button("Receive items") { confirmation = "items" }.disabled(letter.items.isEmpty)
                                }.frame(minHeight: 44).disabled(session.rodex.pending != nil)
                                Button("Delete mail") { confirmation = "delete" }.frame(minHeight: 44)
                                    .disabled(letter.zeny > 0 || !letter.items.isEmpty || session.rodex.pending != nil)
                            }
                        }
                        if let message = session.rodex.message { Text(message) }
                    }.padding(12)
                }.font(.game(size: 13)).buttonStyle(.game)
            }
            .overlay {
                if let item = selected {
                    GameNumberInputBox("Amount", bounds: 1...max(1,min(item.amount,Int(Int16.max)))) { amount in
                        session.attachRodex(index: item.index, amount: amount); selected = nil
                    } onClose: { selected = nil }
                }
            }
        }
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { !confirmation.isEmpty }, set: { if !$0 { confirmation = "" } })) {
            Button("Confirm") {
                switch confirmation {
                case "send": session.sendRodex(receiver: receiver, title: title, text: text, zeny: zeny)
                case "items": session.claimRodex(items: true)
                case "zeny": session.claimRodex(items: false)
                case "delete": session.deleteRodex()
                default: break
                }; confirmation = ""
            }
            Button("Cancel", role: .cancel) { confirmation = "" }
        }
    }
    private var confirmationTitle: String {
        switch confirmation {
        case "send": "Send the listed items and \(zeny.isEmpty ? "0" : zeny) Zeny to \(receiver)? Postage may apply."
        case "delete": "Permanently delete this mail?"
        case "items": "Receive these attached items?"
        default: "Receive attached Zeny?"
        }
    }
    private func itemName(_ id: UInt32) -> String { context.itemInfoTable.localizedIdentifiedItemName(forItemID: Int(id)) ?? "Item \(id)" }
    @ViewBuilder private var compose: some View {
        TextField("Recipient", text: $receiver).textFieldStyle(.roundedBorder)
        Button("Check recipient") { session.checkRodexReceiver(receiver) }.frame(minHeight: 44)
        if let checked = session.rodex.receiver, checked.Name == receiver { Text("\(checked.Name) · Lv. \(checked.BaseLevel)") }
        TextField("Subject", text: $title).textFieldStyle(.roundedBorder)
        TextField("Message", text: $text, axis: .vertical).lineLimit(3...8).textFieldStyle(.roundedBorder)
        TextField("Zeny", text: $zeny).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
        ForEach(session.rodex.attachments.keys.sorted(), id: \.self) { index in
            if let item = session.rodex.attachments[index] {
                HStack { Text("\(itemName(item.itemId)) ×\(item.count)"); Spacer(); Button("Remove") { session.removeRodex(index: index) } }.frame(minHeight: 44)
            }
        }
        DisclosureGroup("Attach inventory item") {
            ForEach(session.inventory.items.values.sorted(), id: \.index) { item in
                if !item.isEquipped {
                    Button { selected = item } label: {
                        HStack { InventoryItemView(item: item); Text(itemName(UInt32(item.itemID))); Spacer(); Text("×\(item.amount)") }.frame(minHeight: 44)
                    }
                }
            }
        }
        HStack {
            Text(RodexState.outgoingUnavailable).foregroundStyle(.secondary)
            Button("Send") { confirmation = "send" }.disabled(true)
            Button("Cancel letter") { session.cancelRodex() }
        }.frame(minHeight: 44).disabled(session.rodex.pending != nil)
    }
}
