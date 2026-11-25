import SwiftUI

struct BankView: View {
    @Environment(PlaySession.self) private var session
    @State private var amount = ""
    @State private var confirmation: Bool?
    var body: some View {
        GeometryReader { bounds in
            OriginalROPanel(title: "Bank", width: min(280, bounds.size.width - 24), height: min(200, bounds.size.height - 24), onClose: { session.closeBank() }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text("Bank"); Spacer(); Text(session.bank.balance.map { "\($0) Zeny" } ?? "—").monospacedDigit() }
                        HStack { Text("Carrying"); Spacer(); Text("\(session.playerStatus.zeny) Zeny").monospacedDigit() }
                        Divider()
                        HStack(spacing: 8) {
                            GameImage("bank/bg_bank.bmp")
                                .frame(width: 280, height: 136).offset(x: -30, y: -60)
                                .frame(width: 38, height: 40, alignment: .topLeading).clipped()
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Amount")
                                TextField("Amount", text: $amount).keyboardType(.numberPad).textFieldStyle(ROTextFieldStyle())
                            }
                            VStack(spacing: 2) {
                                Button("Deposit") { confirmation = true }
                                Button("Withdraw") { confirmation = false }
                            }.frame(width: 78)
                                .disabled(!session.bank.authorized || session.bank.pending != nil || (Int32(amount) ?? 0) <= 0)
                        }.padding(6).background(Color(white: 0.91))
                        if let message = session.bank.message { Text(message).fixedSize(horizontal: false, vertical: true) }
                    }.padding(10)
                }.scrollDismissesKeyboard(.interactively)

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
