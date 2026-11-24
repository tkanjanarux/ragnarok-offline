import SwiftUI

struct ChatRoomView: View {
    @Environment(PlaySession.self) private var session
    @State private var title = ""
    @State private var password = ""
    @State private var limit = 10
    @State private var managing: String?
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: "Chat rooms", width: min(440, bounds.size.width - 24), height: min(540, bounds.size.height - 24), onClose: { session.chatRoom.visible = false }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if session.chatRoom.active {
                            Text(session.chatRoom.title).fontWeight(.bold)
                            Text("Use Local chat to talk in this room.")
                            ForEach(session.chatRoom.members.keys.sorted(), id: \.self) { name in
                                HStack {
                                    Text(name + (session.chatRoom.members[name] == true ? " (Owner)" : ""))
                                    Spacer()
                                    if session.chatRoom.members[session.character.name] == true && name != session.character.name {
                                        Button("Manage") { managing = name }.disabled(session.chatRoom.waiting != nil)
                                    }
                                }.frame(minHeight: 44)
                            }
                            Button("Leave room") { session.leaveChatRoom() }.frame(minHeight: 44)
                        } else {
                            Text("Nearby rooms")
                            ForEach(session.chatRoom.rooms.values.sorted { $0.id < $1.id }) { room in
                                Button { session.joinChatRoom(id: room.id, password: password) } label: {
                                    Text("\(room.title) · \(room.count)/\(room.limit)" + (room.isPrivate ? " · Private" : ""))
                                }.frame(minHeight: 44).disabled(session.chatRoom.waiting != nil)
                            }
                            if session.chatRoom.rooms.isEmpty { Text("No player chat rooms nearby.") }
                        }
                        if !session.chatRoom.active || session.chatRoom.members[session.character.name] == true {
                            Divider()
                            TextField("Room title", text: $title).textFieldStyle(.roundedBorder)
                            SecureField("Password (optional)", text: $password).textFieldStyle(.roundedBorder)
                            Stepper("Limit: \(limit)", value: $limit, in: 2...20)
                            Button(session.chatRoom.active ? "Update room" : "Create room") {
                                session.configureChatRoom(title: title, limit: limit, password: password)
                            }.frame(minHeight: 44).disabled(session.chatRoom.waiting != nil || title.isEmpty)
                        }
                        if let message = session.chatRoom.message { Text(message) }
                    }.padding(12)
                }.font(.game(size: 13)).buttonStyle(.game)
            }
        }
        .confirmationDialog("Manage \(managing ?? "member")", isPresented: Binding(get: { managing != nil }, set: { if !$0 { managing = nil } })) {
            Button("Transfer ownership") { if let name = managing { session.manageChatMember(name, transfer: true) }; managing = nil }
            Button("Remove member", role: .destructive) { if let name = managing { session.manageChatMember(name, transfer: false) }; managing = nil }
            Button("Cancel", role: .cancel) { managing = nil }
        }
    }
}
