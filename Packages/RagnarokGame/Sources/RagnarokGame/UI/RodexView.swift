import SwiftUI
import RagnarokModels
import RagnarokPackets

struct RodexView: View {
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var receiver = ""
    @State private var title = ""
    @State private var text = ""
    @State private var zeny = "0"
    @State private var selected: InventoryItem?
    @State private var confirmation = ""
    @State private var query = ""
    @State private var filter = 0
    @State private var page = 0
    private var filtered: [RodexList.Entry] {
        session.rodex.entries.filter {
            (filter == 0 || (filter == 1 ? !$0.read : $0.attachments != 0)) &&
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.sender.localizedCaseInsensitiveContains(query))
        }
    }
    private var lastPage: Int { max(0, (filtered.count - 1) / 6) }
    private var visibleEntries: [RodexList.Entry] { Array(filtered.dropFirst(min(page, lastPage) * 6).prefix(6)) }
    var body: some View {
        GeometryReader { bounds in
            OriginalROPanel(title: "RODEX", width: min(340, bounds.size.width - 24), height: min(440, bounds.size.height - 24), onClose: { session.closeRodex() }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if session.rodex.writing { compose.disabled(session.rodex.pending != nil) }
                        else {
                            HStack {
                                Text("RodEx").font(.game(size: 22)).bold().foregroundStyle(Color(red: 0.47, green: 0.66, blue: 0.80))
                                Spacer()
                                ROSkinButton(title: "Refresh", image: "basic_interface/rodexsystem/renewal/btn_refresh_out.bmp") { session.openRodex() }
                                ROSkinButton(title: "Write", image: "basic_interface/rodexsystem/renewal/btn_write_out.bmp") { session.beginRodex() }
                            }.disabled(session.rodex.pending != nil)
                            TextField("Search title or sender", text: $query).textFieldStyle(ROTextFieldStyle())
                            ROTabs(choices: [(0, "Inbox"), (1, "Unread"), (2, "Attachments")], selection: $filter)
                            if filtered.isEmpty && session.rodex.pending == nil { Text(session.rodex.entries.isEmpty ? "No mail." : "No matching mail.") }
                            ForEach(visibleEntries, id: \.id) { entry in
                                Button { session.readRodex(entry) } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: entry.read ? "envelope.open" : "envelope").foregroundStyle(Color(red: 0.47, green: 0.53, blue: 0.67))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(entry.title).fontWeight(entry.read ? .regular : .bold)
                                            Text("From: \(entry.sender)").foregroundStyle(Color.blue)
                                        }
                                        Spacer(minLength: 0)
                                        if entry.attachments != 0 { Image(systemName: "paperclip").accessibilityLabel("Attachments") }
                                    }.padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain).disabled(session.rodex.pending != nil)
                                Divider()
                            }
                            HStack {
                                Text("\(filtered.count) mail")
                                Spacer()
                                Button("‹") { page = max(0, page - 1) }.frame(width: 30).disabled(page == 0)
                                Text("\(min(page, lastPage) + 1) / \(lastPage + 1)").monospacedDigit()
                                Button("›") { page = min(lastPage, page + 1) }.frame(width: 30).disabled(page >= lastPage)
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
                                }.frame(minHeight: 30).disabled(session.rodex.pending != nil)
                                Button("Delete mail") { confirmation = "delete" }.frame(minHeight: 30)
                                    .disabled(letter.zeny > 0 || !letter.items.isEmpty || session.rodex.pending != nil)
                            }
                        }
                        if let message = session.rodex.message { Text(message) }
                    }.padding(8)
                }.font(.game(size: 12)).scrollDismissesKeyboard(.interactively)
            }
            .overlay {
                if let item = selected {
                    GameNumberInputBox("Amount", bounds: 1...max(1,min(item.amount,Int(Int16.max)))) { amount in
                        session.attachRodex(index: item.index, amount: amount); selected = nil
                    } onClose: { selected = nil }
                }
            }
        }
        .onChange(of: query) { page = 0 }
        .onChange(of: filter) { page = 0 }
        .onChange(of: lastPage) { page = min(page, lastPage) }
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
        TextField("Recipient", text: $receiver).textFieldStyle(ROTextFieldStyle())
        Button("Check recipient") { session.checkRodexReceiver(receiver) }.frame(minHeight: 30)
        if let checked = session.rodex.receiver, checked.Name == receiver { Text("\(checked.Name) · Lv. \(checked.BaseLevel)") }
        TextField("Subject", text: $title).textFieldStyle(ROTextFieldStyle())
        TextField("Message", text: $text, axis: .vertical).lineLimit(3...8).textFieldStyle(ROTextFieldStyle())
        TextField("Zeny", text: $zeny).keyboardType(.numberPad).textFieldStyle(ROTextFieldStyle())
        ForEach(session.rodex.attachments.keys.sorted(), id: \.self) { index in
            if let item = session.rodex.attachments[index] {
                HStack { Text("\(itemName(item.itemId)) ×\(item.count)"); Spacer(); Button("Remove") { session.removeRodex(index: index) } }.frame(minHeight: 30)
            }
        }
        DisclosureGroup("Attach inventory item") {
            ForEach(session.inventory.items.values.sorted(), id: \.index) { item in
                if !item.isEquipped {
                    Button { selected = item } label: {
                        HStack { InventoryItemView(item: item); Text(itemName(UInt32(item.itemID))); Spacer(); Text("×\(item.amount)") }.frame(minHeight: 30)
                    }
                }
            }
        }
        HStack {
            if !session.rodex.outgoingAllowed { Text(RodexState.outgoingUnavailable).foregroundStyle(.secondary) }
            Button("Send") { confirmation = "send" }.disabled(!session.rodex.outgoingAllowed || session.rodex.pending != nil || session.rodex.receiver?.Name != receiver)
            Button("Cancel letter") { session.cancelRodex() }
        }.frame(minHeight: 30).disabled(session.rodex.pending != nil)
    }
}
