import Foundation
import RagnarokPackets

struct SocialState {
    enum Channel: String, CaseIterable { case local = "Local", party = "Party", guild = "Guild", whisper = "Whisper" }
    struct Friend: Identifiable {
        var accountID: UInt32
        var characterID: UInt32
        var name: String
        var online: Bool?
        var id: String { "\(accountID):\(characterID)" }
    }
    var channel = Channel.local
    var recipient = ""
    var lastWhisperSender: String?
    var whisperPending: (token: UUID, recipient: String, text: String)?
    var friends: [Friend] = []
    var friendsVisible = false
    var invitation: Friend?
    var friendPending: UUID?
    var friendMessage: String?
    mutating func receive(_ packet: PACKET_ZC_FRIENDS_LIST) {
        friends = packet.friends.map { Friend(accountID: $0.AID, characterID: $0.CID, name: $0.name, online: false) }
    }
    mutating func receive(_ packet: PACKET_ZC_FRIENDS_STATE) {
        guard let index = friends.firstIndex(where: { $0.accountID == packet.AID && $0.characterID == packet.CID }) else { return }
        friends[index].online = packet.offline == 0
        if !packet.name.isEmpty { friends[index].name = packet.name }
    }
    mutating func receive(_ packet: FriendAdded) {
        friendPending = nil; invitation = nil
        guard packet.result == 0 else {
            friendMessage = packet.result == 1 ? "Friend invitation declined." : "The friend list is full or the invitation was rejected."
            return
        }
        friends.removeAll { $0.accountID == packet.accountID && $0.characterID == packet.characterID }
        friends.append(.init(accountID: packet.accountID, characterID: packet.characterID, name: packet.name, online: true))
        friendMessage = "Friend added."
    }
    mutating func receive(_ packet: FriendRemoved) {
        friends.removeAll { $0.accountID == packet.accountID && $0.characterID == packet.characterID }
        friendPending = nil; friendMessage = "Friend removed."
    }
}

extension PlaySession {
    func sendChannelChat(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if social.channel == .local || value.hasPrefix("@") || value.hasPrefix("/") || value.hasPrefix("%") || value.hasPrefix("$") {
            sendMessage(value); return true
        }
        return sendSocialText(value, channel: social.channel, recipient: social.recipient)
    }
    func sendSocialText(_ text: String, channel: SocialState.Channel, recipient: String = "") -> Bool {
        let value = channel == .whisper ? text : "\(character.name) : \(text)"
        guard !text.isEmpty, !text.contains("\0"), value.utf8.count <= 254 else {
            socialMessage("Message is empty or too long."); return false
        }
        if channel == .whisper {
            guard social.whisperPending == nil, !recipient.isEmpty, recipient.utf8.count <= 23, !recipient.contains("\0") else {
                socialMessage("Enter a recipient and wait for the previous whisper result."); return false
            }
            let token = UUID()
            social.whisperPending = (token, recipient, text)
            sendFoundationPacket(ChannelChatRequest(channel: .whisper, text: text, recipient: recipient))
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.social.whisperPending?.token == token else { return }
                self.socialMessage("Whisper delivery is unconfirmed. Reconnect before sending another whisper.")
            }
        } else {
            sendFoundationPacket(ChannelChatRequest(channel: channel == .party ? .party : .guild, text: value))
        }
        return true
    }
    func receiveWhisperResult(_ packet: PACKET_ZC_ACK_WHISPER) {
        guard let pending = social.whisperPending else { return }
        social.whisperPending = nil
        if packet.result == 0 { socialMessage("To \(pending.recipient): \(pending.text)") }
        else {
            let reason = packet.result == 1 ? "player is offline" : packet.result == 2 ? "player is blocking whispers" : "whisper was rejected"
            socialMessage("\(pending.recipient): \(reason).")
        }
    }
    func inviteFriend(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard social.friendPending == nil, !name.isEmpty, name.utf8.count <= 23, !name.contains("\0") else { return }
        sendFoundationPacket(FriendRequest.invite(name: name)); scheduleFriendTimeout()
    }
    func replyToFriend(accept: Bool) {
        guard let friend = social.invitation else { return }
        sendFoundationPacket(FriendRequest.reply(accountID: friend.accountID, characterID: friend.characterID, accept: accept))
        social.invitation = nil
        if accept { scheduleFriendTimeout() }
    }
    func removeFriend(_ friend: SocialState.Friend) {
        guard social.friendPending == nil, social.friends.contains(where: { $0.id == friend.id }) else { return }
        sendFoundationPacket(FriendRequest.remove(accountID: friend.accountID, characterID: friend.characterID))
        scheduleFriendTimeout()
    }
    private func scheduleFriendTimeout() {
        let token = UUID(); social.friendPending = token; social.friendMessage = "Waiting for the server…"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, self.social.friendPending == token else { return }
            self.social.friendMessage = "No friend response yet. The player may be offline or still deciding."
            self.social.friendPending = nil // no inventory/zeny mutation; late ACK still updates by identity
        }
    }
    func socialMessage(_ text: String) {
        messageCenter.messages.append(.init(content: text, type: .info, category: .general))
    }
}
