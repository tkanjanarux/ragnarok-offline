import SwiftUI
public struct CompanionCapture: View {
    @State private var session: PlaySession
    public init() {
        let s = PlaySession(context: .testing)
        s.companions.ready = true
        s.companions.available = true
        s.companions.profiles = zip([8,7,9,11],["Priest","Knight","Wizard","Hunter"]).enumerated().map { i, pair in
            CompanionProfile(id: UInt32(i+1), job: UInt32(pair.0), level: 87, jobLevel: 46, exp: 0, jobExp: 0, hp: 3200, maxHP: 4000, sp: 450, maxSP: 600, actor: UInt32(i+10), mode: 2, gems: 0, name: "AI-\(pair.1)-\(i+1)", build: ["support","sword","storm","double"][i])
        }
        s.companions.message = ""
        _session = State(initialValue: s)
    }
    public var body: some View {
        ZStack {
            Color(white: 0.32).ignoresSafeArea()
            CompanionView(close: {}).environment(session).environment(GameContext.testing)
        }
    }
}
