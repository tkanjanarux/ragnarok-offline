import SwiftUI

struct RewardsView: View {
    @Environment(PlaySession.self) private var session
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: session.rewards.attendanceVisible ? "Attendance" : "Achievements", width: min(440, bounds.size.width - 24), height: min(540, bounds.size.height - 24), onClose: {
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
                            Text("Rank \(session.rewards.rank) · \(session.rewards.points) points")
                            Text("\(session.rewards.currentPoints) / \(session.rewards.nextPoints)")
                            if session.rewards.entries.isEmpty { Text("No achievement progress received yet.") }
                            ForEach(session.rewards.entries.keys.sorted(), id: \.self) { id in
                                if let entry = session.rewards.entries[id] {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(AchievementCatalog.names[id] ?? "Achievement \(id)").fontWeight(.bold)
                                        Text(entry.rewarded ? "Reward claimed" : entry.completed ? "Completed" : "In progress")
                                        if !entry.completed, let goals = AchievementCatalog.goals[id] {
                                            ForEach(goals.keys.sorted(), id: \.self) { index in
                                                if entry.counts.indices.contains(index), let target = goals[index] {
                                                    Text("Objective \(index + 1): \(entry.counts[index]) / \(target)")
                                                }
                                            }
                                        }
                                        if entry.completed && !entry.rewarded {
                                            Button("Claim reward") { session.claimAchievement(id) }
                                                .disabled(session.rewards.pendingID != nil).frame(minHeight: 44)
                                        }
                                    }
                                    Divider()
                                }
                            }
                            if let message = session.rewards.message { Text(message) }
                        }
                    }.padding(12)
                }.font(.game(size: 13)).buttonStyle(.game)
            }
        }
    }
}
