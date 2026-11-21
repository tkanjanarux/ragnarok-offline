import RagnarokResources
import SwiftUI

/// QuestHelper renewal companion window (342 × 412), independent from the quest list.
struct QuestDetailView: View {
    @Environment(\.locale) private var locale
    @Environment(PlaySession.self) private var playSession
    var quests: [QuestEntry]
    @Bindable var ui: QuestUIState
    var openItem: ((Int) -> Void)? = nil
    @State private var selectedItemID: Int?
    @Environment(GameContext.self) private var gameContext
    var body: some View {
        if let quest = quests.first(where: { $0.id == ui.selectedQuestID }) {
            ClassicGamePanel(title: "Quest Information", width: 342, height: 412, preferredOffset: CGSize(width: 361.5, height: 0), onClose: { ui.selectedQuestID = nil }) {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(questDisplayText(ui.title(for: quest))).font(.game(weight: .bold))
                                .foregroundStyle(Color(red: 0, green: 0, blue: 0.57)).frame(maxWidth: .infinity, minHeight: 45)
                            let info = ui.metadata[quest.id]
                            let step = QuestGuide.steps[String(quest.id)]
                            let locations = QuestGuide.locations[String(quest.id)] ?? []
                            let thai = locale.language.languageCode == .thai
                            if let step {
                                section(thai ? "ขั้นตอนถัดไป" : "Next step")
                                Text(verbatim: step.text(locale: locale)).padding(.horizontal, 10)
                                if quest.id == 4011 && playSession.canAccessExamRoom {
                                    examButton(thai: thai)
                                }
                                if let materials = step.items {
                                    section(thai ? "ของที่ต้องนำไปส่ง" : "Required items")
                                    ForEach(materials, id: \.id) { item in
                                        Button { showItem(item.id) } label: {
                                            QuestRewardRow(itemID: item.id, count: item.count)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                            if let description = [info?.description, info?.summary].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                                section(thai ? "รายละเอียด" : "Description")
                                Text(linkedDescription(description)).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10)
                            }
                            if !locations.isEmpty {
                                section(thai ? "จุดที่เกี่ยวข้อง" : "Quest locations")
                                ForEach(locations, id: \.self) { location in
                                    Text(verbatim: location).padding(.horizontal, 10)
                                }
                            } else if let info, !info.npcMap.isEmpty {
                                Text("\(info.npcMap) (\(info.npcX), \(info.npcY))").padding(.horizontal, 10)
                            }
                            if !quest.objectives.isEmpty {
                                section(thai ? "ความคืบหน้า" : "Objectives")
                                ForEach(quest.objectives) { objective in
                                    Text("\(objective.name)  \(objective.current) / \(objective.required > 0 ? String(objective.required) : "?")")
                                        .padding(.leading, 20)
                                }
                            }
                            if step == nil && locations.isEmpty && (info?.description ?? "").isEmpty && (info?.summary ?? "").isEmpty && (info?.npcMap ?? "").isEmpty && quest.objectives.isEmpty {
                                Text(thai ? "ยังไม่มีคำแนะนำสำหรับเควสขั้นนี้" : "No instructions available for this quest stage.").padding(.horizontal, 10)
                            }
                            if let info, info.rewardEXP != nil || info.rewardJobEXP != nil || !info.rewards.isEmpty {
                                section(thai ? "รางวัล" : "Reward")
                                if let exp = info.rewardEXP { Text("Base EXP: \(exp)").padding(.leading, 20) }
                                if let exp = info.rewardJobEXP { Text("Job EXP: \(exp)").padding(.leading, 20) }
                                ForEach(Array(info.rewards.enumerated()), id: \.offset) { _, reward in
                                    Button { showItem(reward.itemID) } label: {
                                        QuestRewardRow(itemID: reward.itemID, count: reward.count)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.padding(.horizontal, 5).padding(.bottom, 8)
                    }.frame(height: 370)
                    HStack {
                        if quest.expires > 0 {
                            Text(Date(timeIntervalSince1970: Double(quest.expires)), style: .relative).foregroundStyle(.red).lineLimit(1)
                        }
                        Spacer()
                        Button("Close") { ui.selectedQuestID = nil }.buttonStyle(.game).frame(width: 42, height: 20)
                    }.padding(.horizontal, 7).frame(height: 25)
                }.background(alignment: .top) {
                    GameImage("renew_questui/bg_questsub.bmp").frame(width: 342, height: 412).offset(y: -17)
                }.font(.game()).foregroundStyle(Color.gameLabel)
            }
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "ragoff-quest-item", let host = url.host, let id = Int(host), id > 0 else { return .discarded }
                showItem(id)
                return .handled
            })
            .overlay {
                if let selectedItemID {
                    QuestItemDetailView(itemID: selectedItemID) { self.selectedItemID = nil }
                }
            }
            .task { await ui.loadMetadata(resourceManager: gameContext.resourceManager) }
        }
    }
    private func examButton(thai: Bool) -> some View {
        let title: String = switch playSession.examQueueState {
        case .idle: thai ? "เข้าห้องสอบ" : "Join test room"
        case .joining: thai ? "กำลังเข้าห้องสอบ…" : "Joining…"
        case .queued: thai ? "ออกจากคิวสอบ" : "Leave test queue"
        case .leaving: thai ? "กำลังออกจากคิว…" : "Leaving…"
        case .refused: thai ? "เข้าห้องไม่ได้ · ลองอีกครั้ง" : "Couldn’t join · Retry"
        }
        return Button(title) { playSession.requestExamRoom() }
            .buttonStyle(.game)
            .frame(minWidth: 140, minHeight: 30)
            .disabled(playSession.examQueueState == .joining || playSession.examQueueState == .leaving)
            .padding(.horizontal, 10)
    }

    private func showItem(_ id: Int) {
        if let openItem { openItem(id) } else { selectedItemID = id }
    }
    private func linkedDescription(_ source: String) -> AttributedString {
        var result = AttributedString()
        for segment in QuestRichText.parse(source) {
            var part = AttributedString(description: segment.text, defaultColor: .gameLabel)
            if let id = segment.itemID {
                part.link = URL(string: "ragoff-quest-item://\(id)")
                part.foregroundColor = .blue
                part.underlineStyle = .single
            }
            result.append(part)
        }
        return result
    }
    private func section(_ title: String) -> some View {
        HStack(spacing: 5) {
            GameImage("renew_questui/img_poring.bmp").frame(width: 10, height: 9)
            Text(title)
        }.padding(.horizontal, 5)
    }
}

private struct QuestRewardRow: View {
    var itemID: Int
    var count: Int
    @Environment(GameContext.self) private var gameContext
    @State private var icon: Resources.Image?
    var body: some View {
        HStack {
            Group {
                if let icon { Image(decorative: icon.cgImage, scale: 1) } else { Color.clear }
            }.frame(width: 24, height: 24)
            Text("\(gameContext.itemInfoTable.localizedIdentifiedItemName(forItemID: itemID) ?? "Item #\(itemID)") × \(count)")
                .foregroundStyle(.blue)
        }.padding(.leading, 20).task(id: itemID) {
            icon = try? await gameContext.resourceManager.itemIconImage(forItemID: itemID)
        }
    }
}


private struct QuestItemDetailView: View {
    var itemID: Int
    var close: () -> Void
    @Environment(GameContext.self) private var gameContext
    @State private var preview: Resources.Image?
    var body: some View {
        ClassicGamePanel(title: "Item Information", width: 300, height: 240, onClose: close) {
            VStack(alignment: .leading, spacing: 8) {
                Text(gameContext.itemInfoTable.localizedIdentifiedItemName(forItemID: itemID) ?? "Item #\(itemID)")
                    .font(.game(weight: .bold))
                HStack(alignment: .top, spacing: 8) {
                    Group {
                        if let preview { Image(decorative: preview.cgImage, scale: 1) }
                        else { Color.clear }
                    }.frame(width: 75, height: 100).clipped().border(Color.gray)
                    ScrollView {
                        Text(AttributedString(description: gameContext.itemInfoTable.localizedIdentifiedItemDescription(forItemID: itemID) ?? "Description unavailable in client resources.", defaultColor: .gameLabel))
                            .font(.game(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack {
                    Spacer()
                    Button("Close", action: close).buttonStyle(.game).frame(width: 42, height: 20)
                }
            }.padding(8).font(.game()).background(Color.white)
        }.task(id: itemID) {
            preview = try? await gameContext.resourceManager.itemPreviewImage(forItemID: itemID)
        }
    }
}
