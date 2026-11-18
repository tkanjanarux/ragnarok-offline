import SwiftUI

struct QuestLogView: View {
    var quests: [QuestEntry]
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quest Log").font(.headline)
                Spacer()
                Button("Close", action: close)
            }
            ScrollView {
                if quests.isEmpty { Text("No quests received from the server.") }
                ForEach(quests.sorted { $0.id < $1.id }) { quest in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(questTitles[quest.id] ?? "Quest #\(quest.id)").bold()
                        Text(quest.state == 2 ? "Completed" : quest.state == 0 ? "Inactive" : "Active")
                            .font(.caption)
                        ForEach(quest.objectives) { objective in
                            HStack {
                                Text(objective.name)
                                Spacer()
                                Text("\(objective.current) / \(objective.required)")
                                    .monospacedDigit()
                            }
                        }
                        if quest.expires > 0 {
                            Text("Expires: \(Date(timeIntervalSince1970: Double(quest.expires)), style: .relative)")
                                .font(.caption)
                        }
                        if quest.objectives.isEmpty { Text("Talk to the quest NPC for instructions.").font(.caption) }
                        Divider()
                    }
                }
            }
        }
        .padding().frame(maxWidth: 420, maxHeight: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}
