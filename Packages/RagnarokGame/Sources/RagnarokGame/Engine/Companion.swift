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
    var preset: String = "custom"
    var active: Bool { actor != 0 }
    var jobName: String { [1:"Swordman", 2:"Mage", 4:"Acolyte", 7:"Knight", 8:"Priest", 9:"Wizard"][job] ?? "Unknown" }
    var stateName: String { ["Reserve", "Following", "Assisting", "Stopped", "Dead", "Resting"][mode] }
}

/// Versioned, bounded roster snapshots carried in ordinary server notices.
/// A snapshot is published only after its matching end frame and exact row count.
struct CompanionItemDetails: Equatable {
    let refine: Int
    let cards: [UInt32]
    static let plain = Self(refine: 0, cards: [])

    static func parse(_ fields: ArraySlice<String>) -> Self? {
        if fields.isEmpty { return .plain }
        guard fields.count == 5, let first = fields.first, let refine = Int(first), (0...20).contains(refine) else { return nil }
        let cards = fields.dropFirst().compactMap(UInt32.init)
        guard cards.count == 4 else { return nil }
        return Self(refine: refine, cards: cards.filter { $0 != 0 })
    }
}
struct CompanionEquipment: Identifiable, Equatable {
    let id: UInt32
    let itemID: UInt32
    let equipped: Bool
    let returning: Bool
    var details = CompanionItemDetails.plain
}
struct CompanionBagItem: Identifiable, Equatable {
    let id: UInt32 // native one-based inventory slot
    let itemID: UInt32
    let uniqueID: UInt64
    var details = CompanionItemDetails.plain
}
struct CompanionStarter: Identifiable, Equatable {
    let id: UInt32
    let itemID: UInt32
    let equipped: Bool
}
struct CompanionGearRow: Identifiable {
    let id: String
    let itemID: UInt32
    let detail: String
    var details = CompanionItemDetails.plain
}
extension CompanionState {
    var gearRows: [CompanionGearRow] {
        equipment.map { item in
            CompanionGearRow(id: "gear:\(item.id)", itemID: item.itemID, detail: item.returning ? "Returning…" : item.equipped ? "Your equipment · Equipped" : "Your equipment · Stored", details: item.details)
        } + starters.map { item in
            CompanionGearRow(id: "starter:\(item.id)", itemID: item.itemID, detail: item.equipped ? "Starter · Equipped · Cannot transfer" : "Starter · Fallback · Cannot transfer")
        }
    }
}
struct CompanionSkill: Identifiable, Equatable {
    let id: UInt32
    let level: UInt32
    let maximum: UInt32
    let unlock: UInt32
    let sp: UInt32
    let reason: Int
    static let passives: [UInt32:String] = [
        2:"Sword Mastery", 3:"Two-Handed Sword Mastery", 4:"Increase HP Recovery",
        9:"Increase SP Recovery", 22:"Divine Protection", 23:"Demon Bane", 55:"Spear Mastery"
    ]
    var isPassive: Bool { Self.passives[id] != nil }
    var name: String { Self.passives[id] ?? [60:"Two-Hand Quicken", 56:"Pierce", 59:"Spear Boomerang", 66:"Impositio Manus", 73:"Kyrie Eleison", 75:"Gloria", 86:"Water Ball", 5:"Bash",6:"Provoke",8:"Endure",62:"Bowling Bash",33:"Angelus",74:"Magnificat",19:"Fire Bolt",14:"Cold Bolt",20:"Lightning Bolt",90:"Earth Spike",84:"Jupitel Thunder",28:"Heal",34:"Blessing",29:"Increase AGI",54:"Resurrection"][id] ?? "Skill #\(id)" }
    var policyKey: String? { [60:"quicken", 56:"pierce", 59:"spearboomerang", 66:"impositio", 73:"kyrie", 75:"gloria", 86:"waterball", 5:"bash", 6:"provoke", 8:"endure", 62:"bowlingbash", 33:"angelus", 74:"magnificat", 19:"firebolt", 14:"coldbolt", 20:"lightningbolt", 90:"earthspike", 84:"jupitelthunder", 28:"heal", 34:"blessing", 29:"agi", 54:"resurrection"][id] }
    func toggling(in order: [String]) -> [String] {
        guard let key = policyKey else { return order }
        if order.contains(key) { return order.filter { $0 != key } }
        // Insert conditional skills before repeatable attacks that could starve them.
        let fallbacks: [String]
        switch key {
        case "quicken": fallbacks = ["pierce", "spearboomerang", "bowlingbash", "bash"]
        case "pierce": fallbacks = ["spearboomerang", "bowlingbash", "bash"]
        case "spearboomerang": fallbacks = ["bowlingbash", "bash"]
        case "waterball": fallbacks = ["coldbolt"]
        case "kyrie": fallbacks = ["blessing", "agi", "angelus", "magnificat", "impositio", "gloria"]
        default: fallbacks = []
        }
        var updated = order
        let index = order.firstIndex(where: fallbacks.contains) ?? order.endIndex
        updated.insert(key, at: index)
        return updated
    }
    var status: String { ["Ready", "Unlocks at Job \(unlock)", "Summon to use", "Companion is dead", "Skills disabled", "Not enough SP", "No Blue Gemstone", "Cast delay"][reason] }
}
struct CompanionSupply: Identifiable, Equatable {
    let id: UInt32 // item id for stock, inventory slot for player bag
    let itemID: UInt32
    let amount: UInt32
}
struct CompanionState {
    var potionRule: String?
    var detailReady = false
    var starters: [CompanionStarter] = []
    var skills: [CompanionSkill] = []
    var supplies: [CompanionSupply] = []
    var supplyBag: [CompanionSupply] = []
    var suppliesAvailable = false
    var activity = "Refresh to inspect."
    private var detailExpected: (starter: Int, skill: Int, supply: Int, bag: Int, reason: Int, enabled: Bool)?
    private var incomingStarters: [CompanionStarter] = []
    private var incomingSkills: [CompanionSkill] = []
    private var incomingSupplies: [CompanionSupply] = []
    private var incomingSupplyBag: [CompanionSupply] = []
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
    private(set) var nearbyHunt: Bool?
    private var incomingHunt: Bool?
    var ready = false
    var available = false
    var pending = false
    var message = "Waiting for companion roster."
    private(set) var sequence: UInt32 = 0
    private(set) var completedSequence: UInt32 = 0
    private var expected: Int?
    private var incoming: [CompanionProfile] = []
    private var incomingAvailable = false

    func detailRefreshAction(for profileID: UInt32) -> String? {
        guard !pending else { return nil }
        if !ready { return "list" }
        return available ? "inspect \(profileID)" : nil
    }

    mutating func begin(_ action: String = "list") -> UInt32 {
        incomingHunt = nil
        self.action = action; gearExpected = nil; incomingGear = []; incomingBag = []
        detailExpected = nil; incomingStarters = []; incomingSkills = []; incomingSupplies = []; incomingSupplyBag = []
        if action.hasPrefix("equipment ") || action.hasPrefix("inspect ") { equipmentReady = false; detailReady = false }
        sequence = sequence >= 999_999_999 ? 1 : sequence + 1
        pending = true; expected = nil; incoming = []
        message = "Waiting for server…"
        return sequence
    }
    mutating func timeout(_ token: UInt32) {
        guard pending && token == sequence else { return }
        completedSequence = sequence
        pending = false; ready = false; detailReady = false; detailExpected = nil; expected = nil; incoming = []; equipmentReady = false; gearExpected = nil
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
        case "hunt":
            guard expected != nil, incomingHunt == nil, t.count == 4, ["0","1"].contains(t[3]) else { timeout(sequence); return true }
            incomingHunt = t[3] == "1"
        case "row":
            guard let expected, incoming.count < expected, (17...18).contains(t.count),
                  t.count == 17 || ["custom","protect","assist","conserve"].contains(t[17]),
                  let id = UInt32(t[3]), id > 0, id < 95_000_000,
                  let job = UInt32(t[4]), [1,2,4,7,8,9].contains(job),
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
            incoming.append(CompanionProfile(id: id, job: job, level: level, jobLevel: jobLevel, exp: exp, jobExp: jobExp, hp: hp, maxHP: maxHP, sp: sp, maxSP: maxSP, actor: actor, mode: mode, gems: gems, name: t[16], preset: t.count == 18 ? t[17] : "custom"))
        case "gearbegin":
            guard expected != nil, gearExpected == nil, t.count == 7,
                  let profile = UInt32(t[3]), (action == "equipment \(profile)" || action == "inspect \(profile)"),
                  incoming.contains(where: { $0.id == profile }),
                  let gear = Int(t[4]), (0...8).contains(gear),
                  let bag = Int(t[5]), (0...200).contains(bag), t[6] == "0" || t[6] == "1" else { timeout(sequence); return true }
            gearExpected = (profile, gear, bag, t[6] == "1")
        case "gear":
            guard let g = gearExpected, incomingGear.count < g.gear, t.count >= 7, let details = CompanionItemDetails.parse(t.dropFirst(7)),
                  let id = UInt32(t[3]), id > 0, let item = UInt32(t[4]), item > 0,
                  let mask = UInt32(t[5]), t[6] == "0" || t[6] == "1",
                  !incomingGear.contains(where: { $0.id == id }) else { timeout(sequence); return true }
            incomingGear.append(CompanionEquipment(id: id, itemID: item, equipped: mask != 0, returning: t[6] == "1", details: details))
        case "bag":
            guard let g = gearExpected, incomingBag.count < g.bag, t.count >= 6, let details = CompanionItemDetails.parse(t.dropFirst(6)),
                  let slot = UInt32(t[3]), (1...200).contains(slot), let item = UInt32(t[4]), item > 0,
                  let uid = UInt64(t[5]), uid > 0, uid <= UInt64(Int64.max),
                  !incomingBag.contains(where: { $0.id == slot || $0.uniqueID == uid }) else { timeout(sequence); return true }
            incomingBag.append(CompanionBagItem(id: slot, itemID: item, uniqueID: uid, details: details))
        case "detailbegin":
            guard expected != nil, detailExpected == nil, t.count == 10,
                  let profile = UInt32(t[3]), action == "inspect \(profile)", gearExpected?.profile == profile,
                  let starter = Int(t[4]), (0...2).contains(starter),
                  let skill = Int(t[5]), (1...12).contains(skill),
                  let supply = Int(t[6]), (0...10).contains(supply),
                  let bag = Int(t[7]), (0...200).contains(bag),
                  let reason = Int(t[8]), (0...9).contains(reason), ["0","1"].contains(t[9]) else { timeout(sequence); return true }
            detailExpected = (starter,skill,supply,bag,reason,t[9] == "1")
        case "starter":
            guard let d = detailExpected, incomingStarters.count < d.starter, t.count == 6,
                  let id = UInt32(t[3]), id < 2, let item = UInt32(t[4]), [1201,1601,2301].contains(item),
                  ["0","1"].contains(t[5]), !incomingStarters.contains(where: { $0.id == id }) else { timeout(sequence); return true }
            incomingStarters.append(CompanionStarter(id: id,itemID: item,equipped: t[5] == "1"))
        case "skill":
            guard let d = detailExpected, incomingSkills.count < d.skill, t.count == 9,
                  let id = UInt32(t[3]), CompanionSkill.passives[id] != nil || [60,56,59,66,73,75,86,5,6,8,62,33,74,90,84,19,14,20,28,34,29,54].contains(id),
                  let level = UInt32(t[4]), let maximum = UInt32(t[5]), maximum <= 10, level <= maximum,
                  let unlock = UInt32(t[6]), (1...50).contains(unlock), let sp = UInt32(t[7]), sp <= 10000,
                  let reason = Int(t[8]), (0...7).contains(reason), !incomingSkills.contains(where: { $0.id == id }) else { timeout(sequence); return true }
            incomingSkills.append(CompanionSkill(id:id,level:level,maximum:maximum,unlock:unlock,sp:sp,reason:reason))
        case "supply", "supplybag":
            guard let d = detailExpected else { timeout(sequence); return true }
            let bag = t[2] == "supplybag"
            guard t.count == (bag ? 6 : 5), let id = UInt32(t[3]),
                  let item = UInt32(t[bag ? 4 : 3]), [501,502,503,504,505,569,11621,11622,11623,11624].contains(item),
                  let amount = UInt32(t[bag ? 5 : 4]), amount > 0, amount <= (bag ? 30000 : 1000),
                  bag ? ((1...200).contains(id) && incomingSupplyBag.count < d.bag && !incomingSupplyBag.contains(where: { $0.id == id })) : (incomingSupplies.count < d.supply && !incomingSupplies.contains(where: { $0.id == id })) else { timeout(sequence); return true }
            let row = CompanionSupply(id:id,itemID:item,amount:amount)
            if bag { incomingSupplyBag.append(row) } else { incomingSupplies.append(row) }
        case "end":
            guard let expected, incoming.count == expected else { timeout(sequence); return true }
            if let g = gearExpected {
                guard incomingGear.count == g.gear, incomingBag.count == g.bag else { timeout(sequence); return true }
                equipmentProfile = g.profile; equipment = incomingGear; bag = incomingBag
                transferPending = g.busy; equipmentReady = true
            } else if action.hasPrefix("equipment ") { equipmentReady = false }
            if action.hasPrefix("inspect ") {
                guard let d = detailExpected, incomingStarters.count == d.starter, incomingSkills.count == d.skill,
                      incomingSupplies.count == d.supply, incomingSupplyBag.count == d.bag, gearExpected != nil else { timeout(sequence); return true }
                starters = incomingStarters; skills = incomingSkills; supplies = incomingSupplies; supplyBag = incomingSupplyBag
                suppliesAvailable = d.enabled; detailReady = true
                activity = ["In reserve", "Dead — needs revival or camp recovery", "Stopped — actions and potions paused", "Not in owner's party", "Resting to recover HP/SP", "Following — Assist to fight", "Assisting — waiting for target or support need", "Low HP — no HP potions", "Low SP — no SP potions", "Fighting"][d.reason]
            }
            nearbyHunt = incomingHunt
            profiles = incoming; available = incomingAvailable; ready = true; pending = false; completedSequence = sequence
            self.message = t.dropFirst(3).joined(separator: " ")
            if action.hasPrefix("inspect ") {
                potionRule = nil
                if let marker = self.message.range(of: "Auto potion: ", options: .backwards) {
                    potionRule = String(self.message[marker.lowerBound...])
                    self.message = String(self.message[..<marker.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
            }
            self.expected = nil; incoming = []
        default: timeout(sequence)
        }
        return true
    }
}
