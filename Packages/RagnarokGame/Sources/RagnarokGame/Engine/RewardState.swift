import Foundation
import RagnarokPackets

struct RewardState {
    var visible = false
    var entries: [UInt32: AchievementEntry] = [:]
    var points: UInt32 = 0
    var rank: UInt16 = 0
    var currentPoints: UInt32 = 0
    var nextPoints: UInt32 = 0
    var pendingID: UInt32?
    var token: UUID?
    var message: String?
    var attendanceVisible = false
    var attendanceAuthorized = false
    var attendanceCount: Int?
    var attendanceClaimed = false
    var attendanceWaiting: UUID?
    var attendanceMessage: String?
    mutating func receive(_ p: PACKET_ZC_ALL_ACH_LIST) {
        entries = Dictionary(p.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        points = p.points; rank = p.rank; currentPoints = p.currentRankPoints; nextPoints = p.nextRankPoints
    }
    mutating func receive(_ p: PACKET_ZC_ACH_UPDATE) {
        if p.entry.id > 0 { entries[p.entry.id] = p.entry }
        points = p.points; rank = p.rank; currentPoints = p.currentRankPoints; nextPoints = p.nextRankPoints
    }
    mutating func receive(_ p: AchievementRewardResult) {
        guard pendingID == p.id else { return }
        if p.result == 0 { entries[p.id]?.rewarded = true }
        pendingID = nil; token = nil
        message = p.result == 0 ? "Reward claimed. Item rewards are delivered by mail." : "The server rejected this reward claim."
    }
}

extension PlaySession {
    func claimAchievement(_ id: UInt32) {
        guard rewards.pendingID == nil, let entry = rewards.entries[id], entry.completed, !entry.rewarded else { return }
        let token = UUID(); rewards.pendingID = id; rewards.token = token; rewards.message = "Waiting for the server…"
        sendFoundationPacket(RewardRequest.achievement(id))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, self.rewards.token == token else { return }
            self.rewards.message = "No server response. Reconnect before trying again."
        }
    }
    func openAttendance() {
        rewards.attendanceVisible = true
        guard rewards.attendanceWaiting == nil else { return }
        rewards.attendanceAuthorized = false; rewards.attendanceCount = nil
        sendFoundationPacket(RewardRequest.openAttendance); waitForAttendance()
    }
    func claimAttendance() {
        guard rewards.attendanceAuthorized, !rewards.attendanceClaimed, rewards.attendanceWaiting == nil else { return }
        sendFoundationPacket(RewardRequest.claimAttendance); waitForAttendance()
    }
    private func waitForAttendance() {
        let token = UUID(); rewards.attendanceWaiting = token; rewards.attendanceMessage = "Waiting for the server…"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.rewards.attendanceWaiting == token else { return }
            self.rewards.attendanceMessage = "Attendance is unavailable, or the server has not responded."
        }
    }
}
