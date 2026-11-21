import SwiftUI

/// QuestWindow: at most four active, non-cooldown quests; visibility is independent of the list.
struct QuestTrackerView: View {
    @Environment(\.locale) private var locale
    var quests: [QuestEntry]
    @Bindable var ui: QuestUIState
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ui.trackedQuests(quests, now: timeline.date)) { quest in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(questDisplayText(ui.title(for: quest))).foregroundStyle(.yellow).lineLimit(1)
                        let summary = ui.summary(for: quest, locale: locale)
                        if !summary.isEmpty {
                            Text(questDisplayText(summary)).lineLimit(2)
                        }
                        ForEach(quest.objectives) { objective in
                            Text("\(objective.name) (\(objective.current) / \(objective.required > 0 ? String(objective.required) : "?"))")
                        }
                    }
                }
            }
            .font(.game()).foregroundStyle(.white).shadow(color: .black, radius: 1)
            .multilineTextAlignment(.leading)
        }
    }
}
