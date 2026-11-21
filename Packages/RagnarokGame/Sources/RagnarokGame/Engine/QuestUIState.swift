import Foundation
import Observation
import RagnarokResources
import RagnarokScript

/// Renewal Quest / QuestHelper / QuestWindow presentation state. Server state remains in QuestEntry.
@MainActor @Observable
final class QuestUIState {
    enum Tab: Int, CaseIterable {
        case active = 1, feature, inactive, cooldown
        var title: String {
            switch self { case .active: "Active"; case .feature: "Feature"; case .inactive: "Inactive"; case .cooldown: "Cooldown" }
        }
    }
    var tab: Tab = .active
    var selectedQuestID: UInt32?
    var showTracker = true
    var hiddenQuestIDs: Set<UInt32> = []
    var metadata: [UInt32: QuestMetadata] = [:]
    private var metadataLoaded = false

    func loadMetadata(resourceManager: ResourceManager) async {
        guard !metadataLoaded else { return }
        metadataLoaded = true
        metadata = await resourceManager.questMetadata()
    }
    func reset() {
        tab = .active; selectedQuestID = nil; hiddenQuestIDs = []; showTracker = true
    }
    func title(for quest: QuestEntry) -> String {
        let title = metadata[quest.id]?.title ?? ""
        return title.isEmpty ? (questTitles[quest.id] ?? "Quest #\(quest.id)") : title
    }
    func summary(for quest: QuestEntry, locale: Locale) -> String {
        if let step = QuestGuide.steps[String(quest.id)] { return step.text(locale: locale) }
        if let summary = metadata[quest.id]?.summary, !summary.isEmpty { return summary }
        if let objective = quest.objectives.first { return objective.name }
        return QuestGuide.locations[String(quest.id)]?.first ?? ""
    }
    func toggleTracking(_ id: UInt32) {
        if !hiddenQuestIDs.insert(id).inserted { hiddenQuestIDs.remove(id) }
    }
    func category(for quest: QuestEntry, now: Date = .now) -> Tab {
        // Match roBrowser's renewal categorization; future end_time is displayed under Cooldown.
        if quest.expires > 0 && Double(quest.expires) > now.timeIntervalSince1970 { return .cooldown }
        return quest.state == 1 ? .active : .inactive
    }
    func visibleQuests(_ quests: [QuestEntry], now: Date = .now) -> [QuestEntry] {
        quests.filter { category(for: $0, now: now) == tab }.sorted { $0.id < $1.id }
    }
    func trackedQuests(_ quests: [QuestEntry], now: Date = .now) -> [QuestEntry] {
        guard showTracker else { return [] }
        return Array(quests.filter { category(for: $0, now: now) == .active && !hiddenQuestIDs.contains($0.id) }
            .sorted { $0.id < $1.id }.prefix(4))
    }
}
