import Foundation

struct CompanionProfile: Identifiable, Equatable {
    let id: UInt32
    let job: UInt32
    let level: UInt32
    let jobLevel: UInt32
    let exp: UInt64
    let jobExp: UInt64
    let hp: Int64
    let maxHP: UInt32
    let sp: Int64
    let maxSP: UInt32
    let actor: UInt32
    let mode: Int
    let gems: UInt32
    let name: String
    var active: Bool { actor != 0 }
    var jobName: String { job == 7 ? "Knight" : job == 8 ? "Priest" : "Wizard" }
    var stateName: String { ["Reserve", "Following", "Assisting", "Stopped", "Dead", "Resting"][mode] }
}

/// Versioned, bounded roster snapshots carried in ordinary server notices.
/// A snapshot is published only after its matching end frame and exact row count.
struct CompanionState {
    var profiles: [CompanionProfile] = []
    var ready = false
    var available = false
    var pending = false
    var message = "Waiting for companion roster."
    private(set) var sequence: UInt32 = 0
    private var expected: Int?
    private var incoming: [CompanionProfile] = []
    private var incomingAvailable = false

    mutating func begin() -> UInt32 {
        sequence = sequence >= 999_999_999 ? 1 : sequence + 1
        pending = true; expected = nil; incoming = []
        message = "Waiting for server…"
        return sequence
    }
    mutating func timeout(_ token: UInt32) {
        guard pending && token == sequence else { return }
        pending = false; ready = false; expected = nil; incoming = []
        message = "No response. This server may not support Companions. Refresh to try again."
    }
    @discardableResult mutating func receive(_ message: String) -> Bool {
        guard message.hasPrefix("[RCO1] ") else { return false }
        let t = message.split(separator: " ").map(String.init)
        guard t.count >= 3, UInt32(t[1]) == sequence, pending else { return true }
        switch t[2] {
        case "begin":
            guard t.count == 5, let count = Int(t[3]), (0...9).contains(count), t[4] == "0" || t[4] == "1" else { timeout(sequence); return true }
            expected = count; incoming = []; incomingAvailable = t[4] == "1"
        case "row":
            guard let expected, incoming.count < expected, t.count == 17,
                  let id = UInt32(t[3]), id > 0, id < 95_000_000,
                  let job = UInt32(t[4]), [7,8,9].contains(job),
                  let level = UInt32(t[5]), level > 0, level <= 999,
                  let jobLevel = UInt32(t[6]), jobLevel > 0, jobLevel <= 999,
                  let exp = UInt64(t[7]), let jobExp = UInt64(t[8]),
                  let hp = Int64(t[9]), hp >= -1, let maxHP = UInt32(t[10]),
                  let sp = Int64(t[11]), sp >= -1, let maxSP = UInt32(t[12]),
                  let actor = UInt32(t[13]), actor == 0 || (95_000_000..<100_000_000).contains(actor),
                  let mode = Int(t[14]), (0...5).contains(mode),
                  (actor == 0) == (mode == 0), let gems = UInt32(t[15]), gems <= 20,
                  !t[16].isEmpty, t[16].utf8.count <= 23,
                  !incoming.contains(where: { $0.id == id }) else { timeout(sequence); return true }
            incoming.append(CompanionProfile(id: id, job: job, level: level, jobLevel: jobLevel, exp: exp, jobExp: jobExp, hp: hp, maxHP: maxHP, sp: sp, maxSP: maxSP, actor: actor, mode: mode, gems: gems, name: t[16]))
        case "end":
            guard let expected, incoming.count == expected else { timeout(sequence); return true }
            profiles = incoming; available = incomingAvailable; ready = true; pending = false
            self.message = t.dropFirst(3).joined(separator: " ")
            self.expected = nil; incoming = []
        default: timeout(sequence)
        }
        return true
    }
}
