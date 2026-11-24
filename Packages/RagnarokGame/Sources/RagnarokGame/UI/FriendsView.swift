import SwiftUI

struct FriendsView: View {
    @Environment(PlaySession.self) private var session
    @State private var name = ""
    @State private var removing: SocialState.Friend?
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: "Friends", width: min(450, bounds.size.width - 24),
                             height: min(520, bounds.size.height - 24), onClose: { session.social.friendsVisible = false }) {
                VStack(spacing: 8) {
                    if let invitation = session.social.invitation {
                        Text("\(invitation.name) wants to add you as a friend.")
                        HStack {
                            Button("Accept") { session.replyToFriend(accept: true) }
                            Button("Decline") { session.replyToFriend(accept: false) }
                        }.frame(minHeight: 44)
                        Divider()
                    }
                    HStack {
                        TextField("Character name", text: $name).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        Button("Invite") { session.inviteFriend(name) }.frame(minHeight: 44)
                            .disabled(session.social.friendPending != nil || name.isEmpty)
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(session.social.friends) { friend in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(friend.name).fontWeight(.bold)
                                    Text(friend.online == true ? "Online" : friend.online == false ? "Offline" : "Status unavailable")
                                        .foregroundStyle(friend.online == true ? Color.green : Color.secondary)
                                    HStack {
                                        Button("Whisper") {
                                            session.social.channel = .whisper; session.social.recipient = friend.name
                                            session.social.friendsVisible = false
                                        }
                                        Button("Delete") { removing = friend }.disabled(session.social.friendPending != nil)
                                    }.frame(minHeight: 44)
                                }
                                Divider()
                            }
                        }
                    }
                    if let message = session.social.friendMessage { Text(message) }
                }.font(.game(size: 13)).buttonStyle(.game).padding(10)
            }
        }
        .confirmationDialog("Delete this friend?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Delete", role: .destructive) { if let friend = removing { session.removeFriend(friend) }; removing = nil }
            Button("Cancel", role: .cancel) { removing = nil }
        }
    }
}
