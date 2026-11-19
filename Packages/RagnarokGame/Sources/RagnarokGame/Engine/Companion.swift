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
struct CompanionEquipment: Identifiable, Equatable {
    let id: UInt32
    let itemID: UInt32
    let equipped: Bool
    let returning: Bool
}
struct CompanionBagItem: Identifiable, Equatable {
    let id: UInt32 // native one-based inventory slot
    let itemID: UInt32
    let uniqueID: UInt64
}
struct CompanionState {
    var equipmentProfile: UInt32?
    var equipment: [CompanionEquipment] = []
    var bag: [CompanionBagItem] = []
    var transferPending = false
    var equipmentReady = false
    private(set) var action = "list"
    private var gearExpected: (profile: UInt32, gear: Int, bag: Int, busy: Bool)?
    private var incomingGear: [CompanionEquipment] = []
    private var incomingBag: [CompanionBagItem] = []
    var profiles: [CompanionProfile] = []
    var ready = false
    var available = false
    var pending = false
    var message = "Waiting for companion roster."
    private(set) var sequence: UInt32 = 0
    private var expected: Int?
    private var incoming: [CompanionProfile] = []
    private var incomingAvailable = false

    mutating func begin(_ action: String = "list") -> UInt32 {
        self.action = action; gearExpected = nil; incomingGear = []; incomingBag = []
        if action.hasPrefix("equipment ") { equipmentReady = false }
        sequence = sequence >= 999_999_999 ? 1 : sequence + 1
        pending = true; expected = nil; incoming = []
        message = "Waiting for server…"
        return sequence
    }
    mutating func timeout(_ token: UInt32) {
        guard pending && token == sequence else { return }
        pending = false; ready = false; expected = nil; incoming = []; equipmentReady = false; gearExpected = nil
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
        case "gearbegin":
            guard expected != nil, gearExpected == nil, t.count == 7,
                  let profile = UInt32(t[3]), action == "equipment \(profile)",
                  incoming.contains(where: { $0.id == profile }),
                  let gear = Int(t[4]), (0...8).contains(gear),
                  let bag = Int(t[5]), (0...200).contains(bag), t[6] == "0" || t[6] == "1" else { timeout(sequence); return true }
            gearExpected = (profile, gear, bag, t[6] == "1")
        case "gear":
            guard let g = gearExpected, incomingGear.count < g.gear, t.count == 7,
                  let id = UInt32(t[3]), id > 0, let item = UInt32(t[4]), item > 0,
                  let mask = UInt32(t[5]), t[6] == "0" || t[6] == "1",
                  !incomingGear.contains(where: { $0.id == id }) else { timeout(sequence); return true }
            incomingGear.append(CompanionEquipment(id: id, itemID: item, equipped: mask != 0, returning: t[6] == "1"))
        case "bag":
            guard let g = gearExpected, incomingBag.count < g.bag, t.count == 6,
                  let slot = UInt32(t[3]), (1...200).contains(slot), let item = UInt32(t[4]), item > 0,
                  let uid = UInt64(t[5]), uid > 0, uid <= UInt64(Int64.max),
                  !incomingBag.contains(where: { $0.id == slot || $0.uniqueID == uid }) else { timeout(sequence); return true }
            incomingBag.append(CompanionBagItem(id: slot, itemID: item, uniqueID: uid))
        case "end":
            guard let expected, incoming.count == expected else { timeout(sequence); return true }
            if let g = gearExpected {
                guard incomingGear.count == g.gear, incomingBag.count == g.bag else { timeout(sequence); return true }
                equipmentProfile = g.profile; equipment = incomingGear; bag = incomingBag
                transferPending = g.busy; equipmentReady = true
            } else if action.hasPrefix("equipment ") { equipmentReady = false }
            profiles = incoming; available = incomingAvailable; ready = true; pending = false
            self.message = t.dropFirst(3).joined(separator: " ")
            self.expected = nil; incoming = []
        default: timeout(sequence)
        }
        return true
    }
}
