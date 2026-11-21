import RagnarokResources
import SwiftUI

/// Renewal layout from roBrowser Quest/Quest.html and Quest.css (381 × 466).
struct QuestLogView: View {
    @Environment(\.locale) private var locale
    var quests: [QuestEntry]
    @Bindable var ui: QuestUIState
    var setActive: (UInt32, Bool) -> Void
    var close: () -> Void
    @Environment(GameContext.self) private var gameContext
    @State private var background: Resources.Image?

    var body: some View {
        ClassicGamePanel(title: "Quest Information", width: 381, height: 466, onClose: close) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(QuestUIState.Tab.allCases, id: \.rawValue) { tab in
                            Button { ui.tab = tab } label: {
                                ZStack {
                                    if background == nil {
                                        Rectangle().fill(ui.tab == tab ? Color.white : Color(white: 0.85))
                                        Text(tab.title).rotationEffect(.degrees(-90)).fixedSize()
                                    }
                                    Color.clear.contentShape(Rectangle())
                                }
                            }
                                .buttonStyle(.plain).frame(width: 30, height: 100)
                                .accessibilityLabel(tab.title).accessibilityAddTraits(ui.tab == tab ? .isSelected : [])
                        }
                    }.frame(width: 30, height: 420, alignment: .top)
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(ui.visibleQuests(quests, now: timeline.date)) { quest in row(quest, now: timeline.date) }
                            }.padding(.top, 10)
                        }.frame(width: 341, height: 420)
                    }
                }.frame(width: 381, alignment: .leading)
                HStack(spacing: 5) {
                    Button { ui.showTracker.toggle() } label: {
                        QuestControlImage(name: "renew_questui/checkbox_\(ui.showTracker ? "on" : "off").bmp",
                                          fallback: ui.showTracker ? "✓" : "", width: 10, height: 10)
                    }.buttonStyle(.plain).accessibilityLabel("Show Quest").accessibilityValue(ui.showTracker ? "On" : "Off")
                    Text("Show Quest")
                    Spacer()
                    Button("Close", action: close).buttonStyle(.game).frame(width: 42, height: 20)
                }.padding(.leading, 40).padding(.trailing, 7).frame(height: 29)
            }
            .background(alignment: .top) {
                if let background {
                    Image(decorative: background.cgImage, scale: 1)
                        .frame(width: 381, height: 466).offset(y: -17)
                }
            }
            .font(.game()).foregroundStyle(Color.gameLabel)
        }
        .task { await ui.loadMetadata(resourceManager: gameContext.resourceManager) }
        .task(id: ui.tab) {
            let loaded = try? await gameContext.resourceManager.image(
                at: ResourcePath.userInterfaceDirectory.appending(["renew_questui", "bg_quest\(ui.tab.rawValue).bmp"]),
                removesMagentaPixels: true)
            guard !Task.isCancelled else { return }
            background = loaded
        }
    }

    private func row(_ quest: QuestEntry, now: Date) -> some View {
        HStack(spacing: 0) {
            Button { ui.selectedQuestID = quest.id } label: {
                HStack(spacing: 0) {
                    GameImage("renew_questui/\(ui.metadata[quest.id]?.icon ?? "ico_nq.bmp")")
                        .frame(width: 26, height: 29).frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(questDisplayText(ui.title(for: quest))).font(.game(weight: .bold)).foregroundStyle(Color(red: 0, green: 0, blue: 0.57))
                            .lineLimit(1).frame(height: 21)
                        Text(questDisplayText(ui.summary(for: quest, locale: locale))).lineLimit(1).frame(height: 21)
                    }.frame(width: 254, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            VStack(spacing: 0) {
                if ui.category(for: quest, now: now) == .active {
                    Button { ui.toggleTracking(quest.id) } label: {
                        QuestControlImage(name: "renew_questui/bt_check_\(ui.hiddenQuestIDs.contains(quest.id) ? "off" : "on").bmp",
                                          fallback: ui.hiddenQuestIDs.contains(quest.id) ? "" : "✓", width: 14, height: 14)
                    }.buttonStyle(.plain).frame(width: 30, height: 21).accessibilityLabel("Track \(ui.title(for: quest))")
                } else { Color.clear.frame(width: 30, height: 21) }
                if ui.category(for: quest, now: now) != .cooldown && quest.state != 2 {
                    Button { setActive(quest.id, quest.state != 1) } label: {
                        QuestControlImage(name: "renew_questui/\(quest.state == 1 ? "bt_lock_open" : "bt_lock").bmp",
                                          fallback: quest.state == 1 ? "−" : "+", width: 20, height: 17)
                    }.buttonStyle(.plain).frame(width: 30, height: 21)
                        .accessibilityLabel(quest.state == 1 ? "Set inactive" : "Set active")
                } else { Color.clear.frame(width: 30, height: 21) }
            }
        }.frame(width: 330, height: 42).background {
            GameImage("renew_questui/bg_questlist.bmp").frame(width: 330, height: 42)
        }
    }
}

/// RO color codes and link markup are presentation syntax, never quest instructions.
func questDisplayText(_ value: String) -> String {
    value.replacingOccurrences(of: "\\^[0-9a-fA-F]{6}", with: "", options: .regularExpression)
        .replacingOccurrences(of: "<INFO>.*?</INFO>", with: "", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: "</?(?:ITEM|NAVI|URL|TIP)>", with: "", options: [.regularExpression, .caseInsensitive])
}

/// Asset-first finite control; missing GRF skins still expose a usable control.
struct QuestControlImage: View {
    var name: String
    var fallback: String
    var width: CGFloat
    var height: CGFloat
    @Environment(GameContext.self) private var gameContext
    @State private var image: Resources.Image?
    var body: some View {
        Group {
            if let image { Image(decorative: image.cgImage, scale: 1) }
            else { Text(fallback).font(.game(size: 10)).frame(width: width, height: height).background(Color(white: 0.9)).border(Color.gray) }
        }.frame(width: width, height: height).clipped().task(id: name) {
            let loaded = try? await gameContext.resourceManager.image(
                at: ResourcePath.userInterfaceDirectory.appending(name.split(separator: "/").map(String.init)), removesMagentaPixels: true)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
