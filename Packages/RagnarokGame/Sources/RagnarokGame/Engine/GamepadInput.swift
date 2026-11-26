import Foundation

typealias GamepadTargetValidation = @MainActor (UInt32) -> Bool

struct GamepadInput: Sendable {
    enum Button: Int, CaseIterable, Sendable { case a, b, x, y, leftShoulder, rightShoulder, menu, up, down, left, right, rightStick }
    var left = SIMD2<Float>.zero
    var right = SIMD2<Float>.zero
    var buttons: Set<Button> = []
    var leftTrigger = false
    var rightTrigger = false
    var neutral: Bool { GamepadReducer.axis(left) == .zero && GamepadReducer.axis(right) == .zero && buttons.isEmpty && !leftTrigger && !rightTrigger }
}

enum GamepadCommand: Equatable { case primary, pickup, cancel, menu, target(Int), shortcut(row: Int, column: Int), companion(String) }
struct GamepadFrame {
    var cancelAttack = false
    var move: SIMD2<Float>?
    var camera = SIMD2<Float>.zero
    var command: GamepadCommand?
}

/// Pure input policy. No callbacks/actions are buffered across focus or lifecycle changes.
struct GamepadReducer {
    private var previous: Set<GamepadInput.Button> = []
    private var armed = false
    private var gameplayArmed = false
    private var lastTime: Double?
    private var nextMove = -Double.infinity
    private var nextAction = -Double.infinity
    private var consumedMovement: SIMD2<Float>?
    private var lastMovement = SIMD2<Float>.zero

    mutating func reset() { self = Self() }
    mutating func consumeMovementUntilNeutral() { consumedMovement = lastMovement == .zero ? nil : lastMovement }
    static func axis(_ value: SIMD2<Float>) -> SIMD2<Float> {
        guard value.x.isFinite, value.y.isFinite else { return .zero }
        let length = sqrt(value.x * value.x + value.y * value.y)
        guard length > 0.22 else { return .zero }
        return value / length * min(1, (length - 0.22) / 0.78)
    }
    /// Keep enough server-speed cells ahead to cover the 200ms send interval.
    /// This changes only lookahead, never the server's speed or local movement clock.
    static func lookahead(speedMilliseconds: Int) -> Int {
        min(5, max(1, Int(ceil(250 / Double(max(1, speedMilliseconds))))))
    }
    static func worldDirection(_ value: SIMD2<Float>, azimuth: Float) -> SIMD2<Float> {
        let a = -azimuth
        return SIMD2(value.x * cos(a) - value.y * sin(a), value.x * sin(a) + value.y * cos(a))
    }
    mutating func sample(_ input: GamepadInput, now: Double, available: Bool, blocked: Bool) -> GamepadFrame {
        let edges = input.buttons.subtracting(previous)
        let dt = min(0.05, max(0, now - (lastTime ?? now)))
        previous = input.buttons; lastTime = now
        guard available else { consumedMovement = nil; lastMovement = .zero; armed = false; gameplayArmed = false; nextMove = now; nextAction = now; return .init() }
        if !armed { armed = input.neutral; gameplayArmed = input.neutral && !blocked; return .init() }
        // Cancel/menu are UI actions, never shop confirmation. Modifiers turn B into a shortcut.
        if edges.contains(.menu) { consumedMovement = nil; gameplayArmed = false; return .init(command: .menu) }
        if edges.contains(.b) && !input.leftTrigger && !input.rightTrigger { consumedMovement = nil; gameplayArmed = false; return .init(command: .cancel) }
        guard !blocked else { consumedMovement = nil; gameplayArmed = false; return .init() }
        if !gameplayArmed { gameplayArmed = input.neutral; if input.neutral { consumedMovement = nil }; return .init() }
        var frame = GamepadFrame()
        let rawLeft = Self.axis(input.left)
        if let consumed = consumedMovement {
            let dot = rawLeft.x * consumed.x + rawLeft.y * consumed.y
            let lengths = sqrt((rawLeft.x*rawLeft.x + rawLeft.y*rawLeft.y) * (consumed.x*consumed.x + consumed.y*consumed.y))
            if rawLeft == .zero || (lengths > 0 && dot / lengths < cos(25 * .pi / 180)) { consumedMovement = nil }
        }
        lastMovement = rawLeft
        let left = consumedMovement == nil ? rawLeft : SIMD2<Float>.zero
        frame.cancelAttack = left != .zero
        if left != .zero && now >= nextMove { frame.move = left; nextMove = now + 0.2 }
        // Clicking the stick must not orbit the camera from press-induced deflection.
        frame.camera = input.buttons.contains(.rightStick) ? .zero : Self.axis(input.right) * Float(dt)
        guard now >= nextAction else { return frame }
        for button in GamepadInput.Button.allCases where edges.contains(button) {
            let face = [GamepadInput.Button.a, .b, .x, .y].firstIndex(of: button)
            if let face, input.rightTrigger { frame.command = .shortcut(row: 0, column: face + 4) }
            else if let face, input.leftTrigger { frame.command = .shortcut(row: 0, column: face) }
            else {
                switch button {
                case .a: frame.command = .primary; frame.move = nil
                case .x, .rightStick: frame.command = .pickup; frame.move = nil
                case .y: frame.command = .shortcut(row: 0, column: 1)
                case .leftShoulder: frame.command = .target(-1)
                case .rightShoulder: frame.command = .target(1)
                case .up: frame.command = .companion("follow")
                case .right: frame.command = .companion("assist")
                case .down: frame.command = .companion("stop")
                case .left: frame.command = .companion("hunt")
                default: break
                }
            }
            if frame.command != nil { nextAction = now + 0.15; break }
        }
        return frame
    }
}

struct GamepadTargetRing {
    struct Candidate { let id: UInt32; let position: SIMD2<Float> }
    private(set) var order: [UInt32] = []
    private(set) var selected: UInt32?
    mutating func reset() { order = []; selected = nil }
    mutating func update(_ candidates: [Candidate], origin: SIMD2<Float>, facing: SIMD2<Float>) {
        let valid = Set(candidates.map(\.id)); order.removeAll { !valid.contains($0) }
        if let selected, !valid.contains(selected) { self.selected = nil }
        if selected == nil { order = [] }
        let existing = Set(order)
        let added = candidates.filter { !existing.contains($0.id) }.sorted {
            func score(_ c: Candidate) -> Float {
                let d = c.position - origin, length = sqrt(d.x*d.x + d.y*d.y)
                let facingLength = sqrt(facing.x*facing.x + facing.y*facing.y)
                let dot = length > 0 && facingLength > 0 ? (d.x*facing.x + d.y*facing.y) / (length * facingLength) : 1
                return length + (dot < 0.25 ? 1000 : 0)
            }
            let a = score($0), b = score($1)
            return a == b ? $0.id < $1.id : a < b
        }
        order += added.map(\.id)
    }
    @discardableResult mutating func select(_ id: UInt32) -> Bool {
        guard order.contains(id) else { return false }
        selected = id; return true
    }
    mutating func cycle(_ step: Int) -> UInt32? {
        guard !order.isEmpty else { selected = nil; return nil }
        let index = selected.flatMap { order.firstIndex(of: $0) }
        selected = order[index.map { ($0 + (step < 0 ? -1 : 1) + order.count) % order.count } ?? 0]
        return selected
    }
}

/// A cancelled arrival must never revive a previous attack, including the same target ID.
struct GamepadAttackLease {
    private(set) var generation: UInt64 = 0
    private(set) var target: UInt32?
    mutating func begin(_ target: UInt32) -> UInt64 {
        generation &+= 1; self.target = target; return generation
    }
    func accepts(_ token: UInt64, target: UInt32) -> Bool { token == generation && self.target == target }
    @discardableResult mutating func cancel() -> Bool {
        let active = target != nil; generation &+= 1; target = nil; return active
    }
}

/// The UI protocol has per-profile follow/assist/stop and a team hunt command.
/// Serialize those existing acknowledged operations; never send unacknowledged chat verbs.
struct GamepadTeamPlan {
    struct Step: Equatable { let action: String; let success: String }
    private(set) var steps: [Step] = []
    private(set) var members: [UInt32] = []
    mutating func cancel() { steps = []; members = [] }
    mutating func begin(_ verb: String, members: [UInt32], teamMode: Bool, hunt: Bool) -> Bool {
        cancel()
        guard ["follow", "assist", "stop", "hunt"].contains(verb), !members.isEmpty,
              teamMode || hunt, verb != "hunt" || hunt else { return false }
        self.members = members.sorted()
        steps = [.init(action: teamMode ? "teamoff" : "hunt off", success: teamMode ? "Assist mode." : "Nearby hunt OFF.")]
        if verb == "hunt" { steps.append(.init(action: "hunt on", success: "Nearby hunt ON.")) }
        else {
            let success = verb == "follow" ? "Following." : verb == "assist" ? "Assisting." : "Stopped."
            steps += self.members.map { .init(action: "\(verb) \($0)", success: success) }
        }
        return true
    }
    mutating func acknowledge(message: String, ready: Bool, members: [UInt32]) -> Bool {
        guard ready, members.sorted() == self.members, steps.first?.success == message else { cancel(); return false }
        steps.removeFirst(); return true
    }
}

/// Preview is only a proposal. Choosing it never selects a scene entity or sends packets.
struct GamepadDirectionalTargets {
    static let halfConeRadians: Float = 40 * .pi / 180
    static let distanceWeight: Float = 0.08
    static let hysteresis: Float = 0.06
    typealias Candidate = GamepadTargetRing.Candidate
    private(set) var preview: UInt32?
    mutating func reset() { preview = nil }
    mutating func update(_ candidates: [Candidate], origin: SIMD2<Float>, facing: SIMD2<Float>, attackRange: Int = 0) {
        let range = GamepadTargetRange(attackRange: attackRange)
        let length = sqrt(facing.x*facing.x + facing.y*facing.y)
        guard length > 0, length.isFinite else { preview = nil; return }
        let forward = facing / length
        let ranked: [(UInt32, Float)] = candidates.compactMap { c in
            let d = c.position - origin, distance = sqrt(d.x*d.x + d.y*d.y)
            guard distance.isFinite, range.containsSoft(d) else { return nil }
            let dot = distance > 0 ? (d.x*forward.x + d.y*forward.y) / distance : 1
            guard dot >= cos(Self.halfConeRadians) else { return nil }
            return (c.id, acos(min(1,max(-1,dot))) + distance / Float(max(8, attackRange)) * Self.distanceWeight)
        }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
        guard let best = ranked.first else { preview = nil; return }
        if let old = ranked.first(where: { $0.0 == preview }), old.1 <= best.1 + Self.hysteresis { return }
        preview = best.0
    }
    /// Explicit locks override facing, but never bypass current visibility/path validity.
    func resolve(explicit: UInt32?, valid: Set<UInt32>) -> UInt32? {
        if let explicit { return valid.contains(explicit) ? explicit : nil }
        return preview.flatMap { valid.contains($0) ? $0 : nil }
    }
}

struct GamepadFacingIntent {
    private var intent: SIMD2<Float>?
    private var modelDirection: Int?
    mutating func reset() { self = Self() }
    mutating func update(stick: SIMD2<Float>, azimuth: Float, direction: Int) -> SIMD2<Float> {
        if stick != .zero { intent = GamepadReducer.worldDirection(stick, azimuth: azimuth) }
        else if modelDirection != direction { intent = nil }
        modelDirection = direction
        if let intent { return intent }
        let angle = -Float(direction) * .pi / 4 - .pi / 2
        return SIMD2(cos(angle),sin(angle))
    }
}

/// Server range uses the same Chebyshev cell distance as PathFinder/attackMonster.
/// Union with the old approach circles keeps melee usability without changing hit range.
struct GamepadTargetRange {
    let attackRange: Int
    private func contains(_ delta: SIMD2<Float>, approachRadius: Float) -> Bool {
        guard delta.x.isFinite, delta.y.isFinite else { return false }
        return max(abs(delta.x), abs(delta.y)) <= Float(max(0, attackRange))
            || delta.x * delta.x + delta.y * delta.y <= approachRadius * approachRadius
    }
    func containsSoft(_ delta: SIMD2<Float>) -> Bool { contains(delta, approachRadius: 8) }
    func containsLock(_ delta: SIMD2<Float>) -> Bool { contains(delta, approachRadius: 12) }
}
