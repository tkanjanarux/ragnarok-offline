import SwiftUI

struct BankView: View {
    @Environment(PlaySession.self) private var session
    @State private var amount = ""
    @State private var confirmation: Bool?
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: "Bank", width: min(380, bounds.size.width - 24), height: min(360, bounds.size.height - 24), onClose: { session.closeBank() }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Bank: " + (session.bank.balance.map { "\($0) Zeny" } ?? "—"))
                        Text("Carrying: \(session.playerStatus.zeny) Zeny")
                        TextField("Amount", text: $amount).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Deposit") { confirmation = true }
                            Button("Withdraw") { confirmation = false }
                        }.frame(minHeight: 44)
                            .disabled(!session.bank.authorized || session.bank.pending != nil || (Int32(amount) ?? 0) <= 0)
                        if let message = session.bank.message { Text(message) }
                    }.padding(12)
                }.font(.game(size: 14)).buttonStyle(.game)
            }
        }
        .confirmationDialog("Transfer \(amount) Zeny?", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            Button(confirmation == true ? "Deposit" : "Withdraw") {
                if let deposit = confirmation, let value = Int32(amount) { session.transferBank(amount: value, deposit: deposit) }
                confirmation = nil
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        }
    }
}
