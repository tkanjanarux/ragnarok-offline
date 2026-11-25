import SwiftUI

struct RewardsView: View {
    @Environment(PlaySession.self) private var session
    @State private var category = 0
    @State private var group = "All"
    private var groups: [String] { ["All"] + Set(session.rewards.entries.keys.map { AchievementCatalog.groups[$0] ?? "Other" }).sorted() }
    @State private var selectedID: UInt32?
    private var filteredIDs: [UInt32] {
        session.rewards.entries.keys.sorted().filter { id in
            guard let entry = session.rewards.entries[id], group == "All" || (AchievementCatalog.groups[id] ?? "Other") == group else { return false }
            switch category {
            case 1: return !entry.completed
            case 2: return entry.completed && !entry.rewarded
            case 3: return entry.rewarded
            default: return true
            }
        }
    }
    var body: some View {
        GeometryReader { bounds in
            OriginalROPanel(title: session.rewards.attendanceVisible ? "Attendance" : "Achievements", width: min(540, bounds.size.width - 24), height: min(390, bounds.size.height - 24), onClose: {
                session.rewards.visible = false; session.rewards.attendanceVisible = false
            }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if session.rewards.attendanceVisible {
                            if let count = session.rewards.attendanceCount { Text("Days claimed: \(count)") }
                            Text(session.rewards.attendanceClaimed ? "Today's reward has been claimed." : "Rewards are delivered to your mailbox.")
                            Button("Claim today's reward") { session.claimAttendance() }
                                .disabled(!session.rewards.attendanceAuthorized || session.rewards.attendanceClaimed || session.rewards.attendanceWaiting != nil).frame(minHeight: 44)
                            if let message = session.rewards.attendanceMessage { Text(message) }
                        } else {
                            achievements
                            if let message = session.rewards.message { Text(message) }
                        }
                    }.padding(8)
                }.font(.game(size: 12))
            }
        }
    }
    private var achievements: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack {
                    Text("Rank \(session.rewards.rank)").bold()
                    Text("\(session.rewards.currentPoints) / \(session.rewards.nextPoints)").monospacedDigit()
                    ROProgress(value: Double(session.rewards.currentPoints), total: Double(session.rewards.nextPoints))
                }.frame(width: 105)
                Spacer()
                Text("\(session.rewards.points) points").bold().padding(8)
                    .background(Color(red: 0.84, green: 0.89, blue: 0.98))
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 2) {
                    ForEach(groups, id: \.self) { name in
                        Button { group = name; selectedID = nil } label: {
                            Text(LocalizedStringKey(groupTitle(name))).font(.game(size: 11))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(group == name ? Color.blue.opacity(0.15) : Color.clear)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }.frame(width: 90)
                VStack(alignment: .leading, spacing: 7) {
                    ROTabs(choices: [(0, "All"), (1, "In progress"), (2, "Completed"), (3, "Reward claimed")], selection: $category)
                    Text("\(session.rewards.entries.values.filter { $0.completed }.count) / \(session.rewards.entries.count) completed")
                    ROProgress(value: Double(session.rewards.entries.values.filter { $0.completed }.count), total: Double(session.rewards.entries.count))
                    if session.rewards.entries.isEmpty { Text("No achievement progress received yet.") }
                    else if filteredIDs.isEmpty { Text("No achievements in this category.") }
                    ForEach(filteredIDs, id: \.self) { id in
                        achievementRow(id)
                    }
                }
            }

        }
    }

    @ViewBuilder private func achievementRow(_ id: UInt32) -> some View {
        if let entry = session.rewards.entries[id] {
            Button { selectedID = selectedID == id ? nil : id } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AchievementCatalog.names[id] ?? "Achievement \(id)").bold()
                    Text(entry.rewarded ? "Reward claimed" : entry.completed ? "Completed" : "In progress").foregroundStyle(Color.gray)
                }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedID == id ? Color.blue.opacity(0.12) : Color.white)
                    .overlay { Rectangle().strokeBorder(Color.gameBoxBorder) }
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if selectedID == id {
                if !entry.completed, let goals = AchievementCatalog.goals[id] {
                    ForEach(goals.keys.sorted(), id: \.self) { index in
                        if entry.counts.indices.contains(index), let target = goals[index] {
                            Text("Objective \(index + 1): \(entry.counts[index]) / \(target)")
                            ROProgress(value: Double(entry.counts[index]), total: Double(target))
                        }
                    }
                }
                if entry.completed && !entry.rewarded {
                    Button("Claim reward") { session.claimAchievement(id) }
                        .disabled(session.rewards.pendingID != nil)
                }
            }
        }
    }

    private func groupTitle(_ name: String) -> String {
        switch name {
        case "BattleBoss": "Boss battles"
        case "BattleKill": "Monster hunting"
        case "ChatCreate": "Chat rooms"
        case "ChatDying": "Survival"
        case "GetItem": "Items"
        case "GetZeny": "Zeny"
        case "GoalAchieve": "Achievements"
        case "GoalLevel": "Levels"
        case "GoalStatus": "Attributes"
        case "JobChange": "Job changes"
        case "RefineFail": "Failed refining"
        case "RefineSuccess": "Successful refining"
        default: name
        }
    }

}
