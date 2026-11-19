import SwiftUI

/// roBrowser PartyHelper SETUP: the original three radio groups and OK/Cancel footer.
struct PartySetupView: View {
    var close: () -> Void
    @Environment(PlaySession.self) private var session
    @State private var exp = false
    @State private var pickup = false
    @State private var distribution = false
    private var leader: Bool { session.party.members.contains { $0.id == session.partyAccountID && $0.leader } }

    var body: some View {
        ClassicGamePanel(title: "Party Setup", width: 300, height: 350, onClose: close) {
            VStack(alignment: .leading, spacing: 3) {
                radios("How to share EXP", first: "Each Take", second: "Even Share", value: $exp)
                radios("How to share Items", first: "Each Take", second: "Party Share", value: $pickup)
                radios("Item Sharing type", first: "Individual", second: "Shared", value: $distribution)
                Text(verbatim: session.party.shareMessage).font(.game(size: 11))
                    .foregroundStyle(Color.gameLabel).frame(maxWidth: .infinity, alignment: .leading).frame(height: 55)
                    .accessibilityLabel(session.party.shareMessage)
                if !leader { Text("Only the party leader can change these settings.").font(.game(size: 10)) }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button { session.setPartyOptions(exp: exp, pickup: pickup, distribution: distribution) } label: {
                        Text(session.party.optionsPending ? "Waiting…" : "OK").frame(width: 64, height: 32)
                    }.buttonStyle(.game).disabled(!leader || !session.party.optionsReady || session.party.optionsPending)
                    Button("Cancel", action: close).buttonStyle(.game).frame(width: 64, height: 32)
                }.padding(.bottom, 4)
            }.padding(.horizontal, 10).padding(.top, 10)
        }
        .onAppear { syncOptions() }
        .onChange(of: session.party.optionsReady) { syncOptions() }
        .onChange(of: session.party.evenShare) { syncOptions() }
        .onChange(of: session.party.pickupShare) { syncOptions() }
        .onChange(of: session.party.distributionShare) { syncOptions() }
    }

    private func syncOptions() {
        exp = session.party.evenShare; pickup = session.party.pickupShare; distribution = session.party.distributionShare
    }

    private func radios(_ title: String, first: String, second: String, value: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.game(weight: .bold))
            HStack(spacing: 2) {
                radio(first, selected: !value.wrappedValue) { value.wrappedValue = false }
                radio(second, selected: value.wrappedValue) { value.wrappedValue = true }
            }
        }.disabled(!leader || !session.party.optionsReady || session.party.optionsPending)
    }

    private func radio(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                GameImage("radiobtn_\(selected ? "on" : "off").bmp").frame(width: 12, height: 12)
                Text(title).font(.game(size: 11))
                Spacer(minLength: 0)
            }.frame(width: 135, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
