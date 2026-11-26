import Foundation

struct GamepadInput: Sendable {
    enum Button: Int, CaseIterable, Sendable { case a, b, x, y, leftShoulder, rightShoulder, menu, up, down, left, right }
    var left = SIMD2<Float>.zero
    var right = SIMD2<Float>.zero
    var buttons: Set<Button> = []
    var leftTrigger = false
    var rightTrigger = false
    var neutral: Bool { GamepadReducer.axis(left) == .zero && GamepadReducer.axis(right) == .zero && buttons.isEmpty && !leftTrigger && !rightTrigger }
}

enum GamepadCommand: Equatable { case primary, cancel, menu, target(Int), shortcut(row: Int, column: Int), companion(String), nextCompanion }
struct GamepadFrame {
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

    mutating func reset() { self = Self() }
    static func axis(_ value: SIMD2<Float>) -> SIMD2<Float> {
        guard value.x.isFinite, value.y.isFinite else { return .zero }
        let length = sqrt(value.x * value.x + value.y * value.y)
        guard length > 0.22 else { return .zero }
        return value / length * min(1, (length - 0.22) / 0.78)
    }
    static func worldDirection(_ value: SIMD2<Float>, azimuth: Float) -> SIMD2<Float> {
        let a = -azimuth
        return SIMD2(value.x * cos(a) - value.y * sin(a), value.x * sin(a) + value.y * cos(a))
    }
    mutating func sample(_ input: GamepadInput, now: Double, available: Bool, blocked: Bool) -> GamepadFrame {
        let edges = input.buttons.subtracting(previous)
        let dt = min(0.05, max(0, now - (lastTime ?? now)))
        previous = input.buttons; lastTime = now
        guard available else { armed = false; gameplayArmed = false; nextMove = now; nextAction = now; return .init() }
        if !armed { armed = input.neutral; gameplayArmed = input.neutral && !blocked; return .init() }
        // Cancel/menu are UI actions, never shop confirmation. Modifiers turn B into a shortcut.
        if edges.contains(.menu) { gameplayArmed = false; return .init(command: .menu) }
        if edges.contains(.b) && !input.leftTrigger && !input.rightTrigger { gameplayArmed = false; return .init(command: .cancel) }
        guard !blocked else { gameplayArmed = false; return .init() }
        if !gameplayArmed { gameplayArmed = input.neutral; return .init() }
        var frame = GamepadFrame()
        let left = Self.axis(input.left)
        if left != .zero && now >= nextMove { frame.move = left; nextMove = now + 0.2 }
        frame.camera = Self.axis(input.right) * Float(dt)
        guard now >= nextAction else { return frame }
        for button in GamepadInput.Button.allCases where edges.contains(button) {
            let face = [GamepadInput.Button.a, .b, .x, .y].firstIndex(of: button)
            if let face, input.rightTrigger { frame.command = .shortcut(row: 1, column: face) }
            else if let face, input.leftTrigger { frame.command = .shortcut(row: 0, column: face + 2) }
            else {
                switch button {
                case .a: frame.command = .primary
                case .x: frame.command = .shortcut(row: 0, column: 0)
                case .y: frame.command = .shortcut(row: 0, column: 1)
                case .leftShoulder: frame.command = .target(-1)
                case .rightShoulder: frame.command = .target(1)
                case .up: frame.command = .companion("follow")
                case .right: frame.command = .companion("assist")
                case .down: frame.command = .companion("stop")
                case .left: frame.command = .nextCompanion
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
