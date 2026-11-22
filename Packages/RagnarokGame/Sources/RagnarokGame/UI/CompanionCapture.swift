import SwiftUI
public struct CompanionCapture: View {
    @State private var session: PlaySession
    public init() {
        let s = PlaySession(context: .testing)
        let t = s.companions.begin("list")
        for line in ["begin 0 1","team assist 5","hunt 0","voice normal","end Ready"] {
            s.companions.receive("[RCO1] \(t) " + line)
        }
        s.companions.ready = true
        s.companions.available = true
        s.companions.profiles = zip([8,7,9,11],["Priest","Knight","Wizard","Hunter"]).enumerated().map { i, pair in
            CompanionProfile(id: UInt32(i+1), job: UInt32(pair.0), level: 87, jobLevel: 46, exp: 0, jobExp: 0, hp: 3200, maxHP: 4000, sp: 450, maxSP: 600, actor: UInt32(i+10), mode: 2, gems: 0, name: "AI-\(pair.1)-\(i+1)", build: ["support","sword","storm","double"][i])
        }
        s.companions.equipmentProfile = 2
        s.companions.equipmentReady = true
        s.companions.detailReady = true
        s.companions.suppliesAvailable = true
        s.companions.starters = [.init(id: 0, itemID: 1201, equipped: false), .init(id: 1, itemID: 2301, equipped: true)]
        s.companions.equipment = [.init(id: 1, itemID: 1157, equipped: true, returning: false, equipMask: 34)]
        s.companions.supplies = [.init(id: 501, itemID: 501, amount: 12)]
        s.companions.skills = [.init(id: 60, level: 5, maximum: 10, unlock: 12, sp: 34, reason: 0), .init(id: 3, level: 10, maximum: 10, unlock: 1, sp: 0, reason: 0)]
        s.companions.bag = [.init(id: 5, itemID: 1154, uniqueID: 101)]
        s.companions.message = ""
        _session = State(initialValue: s)
    }
    public var body: some View {
        ZStack {
            Color(white: 0.32).ignoresSafeArea()
            Group {
                if ProcessInfo.processInfo.arguments.contains("gear") {
                    CompanionEquipmentView(profileID: 2, close: {})
                } else {
                    CompanionView(close: {})
                }
            }.environment(session).environment(GameContext.testing)
        }
    }
}
