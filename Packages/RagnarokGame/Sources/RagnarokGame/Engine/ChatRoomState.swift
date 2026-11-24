import Foundation
import RagnarokPackets

struct ChatRoomState {
    struct Room: Identifiable { var id: UInt32; var owner: UInt32; var title: String; var limit: Int; var count: Int; var isPrivate: Bool }
    var visible = false
    var rooms: [UInt32: Room] = [:]
    var active = false
    var roomID: UInt32?
    var title = ""
    var members: [String: Bool] = [:] // server role; protocol identifies room members by character name
    var waiting: UUID?
    var creatingTitle: String?
    var joiningID: UInt32?
    var message: String?
    mutating func receive(_ p: PACKET_ZC_ROOM_NEWENTRY) {
        guard p.type < 2, p.id > 0, p.owner > 0 else { return } // never mix NPC exam/waiting rooms
        rooms[UInt32(p.id)] = .init(id: UInt32(p.id), owner: UInt32(p.owner), title: p.title, limit: Int(p.limit), count: Int(p.users), isPrivate: p.type == 0)
    }
    mutating func receive(_ p: PACKET_ZC_ENTER_ROOM) {
        guard joiningID == p.chatId else { return }
        roomID = p.chatId; active = true; title = rooms[p.chatId]?.title ?? "Chat room"
        members = Dictionary(p.members.map { ($0.name, $0.flag == 0) }, uniquingKeysWith: { _, newest in newest })
        waiting = nil; joiningID = nil; message = nil
    }
    mutating func leave() { active = false; roomID = nil; members = [:]; waiting = nil; joiningID = nil; creatingTitle = nil }
}

extension PlaySession {
    func configureChatRoom(title: String, limit: Int, password: String) {
        guard chatRoom.waiting == nil, !trade.active, !chatRoom.active || chatRoom.members[character.name] == true,
              !title.isEmpty, title.utf8.count <= 60, !title.contains("\0"), (2...20).contains(limit), password.utf8.count <= 7, !password.contains("\0") else { return }
        if !chatRoom.active { chatRoom.creatingTitle = title }
        sendFoundationPacket(ChatRoomRequest.configure(title: title, limit: UInt16(limit), password: password, editing: chatRoom.active)); waitForChatRoom()
    }
    func joinChatRoom(id: UInt32, password: String) {
        guard !chatRoom.active, chatRoom.waiting == nil, chatRoom.rooms[id] != nil, password.utf8.count <= 7, !password.contains("\0"), examQueueState == .idle else { return }
        chatRoom.joiningID = id
        sendFoundationPacket(ChatRoomRequest.join(id, password)); waitForChatRoom()
    }
    func leaveChatRoom() {
        guard chatRoom.active else { chatRoom.visible = false; return }
        sendFoundationPacket(ChatRoomRequest.leave); waitForChatRoom()
    }
    func manageChatMember(_ name: String, transfer: Bool) {
        guard chatRoom.active, chatRoom.waiting == nil, chatRoom.members[character.name] == true,
              name != character.name, chatRoom.members[name] != nil else { return }
        sendFoundationPacket(transfer ? ChatRoomRequest.owner(name) : ChatRoomRequest.kick(name)); waitForChatRoom()
    }
    private func waitForChatRoom() {
        let token = UUID(); chatRoom.waiting = token; chatRoom.message = "Waiting for the server…"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.chatRoom.waiting == token else { return }
            self.chatRoom.message = "No server response. Reconnect to refresh the room."
        }
    }
}
