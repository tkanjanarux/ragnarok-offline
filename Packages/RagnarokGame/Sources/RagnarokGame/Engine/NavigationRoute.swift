import Foundation
import RagnarokScript

/// Full-map guidance search. The movement PathFinder's 32-cell packet limit is
/// deliberately unchanged. No movement packets are emitted by navigation.
struct NavigationGrid: Sendable {
    var width: Int
    var height: Int
    var walkable: [Bool]
    func contains(_ p: SIMD2<Int>) -> Bool { p.x >= 0 && p.y >= 0 && p.x < width && p.y < height }
    func canWalk(_ p: SIMD2<Int>) -> Bool { contains(p) && walkable[p.y * width + p.x] }
    func paths(from start: SIMD2<Int>) -> NavigationPaths {
        var parents = [Int](repeating: -1, count: width * height)
        guard canWalk(start) else { return .init(grid: self, parents: parents, start: start) }
        let first = start.y * width + start.x
        parents[first] = first
        var queue = [first], cursor = 0
        while cursor < queue.count {
            if cursor % 1024 == 0 && Task.isCancelled { break }
            let index = queue[cursor]; cursor += 1
            let point = SIMD2(index % width, index / width)
            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                let next = point &+ SIMD2(dx, dy)
                guard canWalk(next), (dx == 0 || dy == 0 ||
                    (canWalk(point &+ SIMD2(dx, 0)) && canWalk(point &+ SIMD2(0, dy)))) else { continue }
                let n = next.y * width + next.x
                if parents[n] == -1 { parents[n] = index; queue.append(n) }
            } }
        }
        return .init(grid: self, parents: parents, start: start)
    }
}

struct NavigationPaths {
    var grid: NavigationGrid
    var parents: [Int]
    var start: SIMD2<Int>
    func path(to target: SIMD2<Int>, range: Int = 0) -> [SIMD2<Int>]? {
        guard grid.contains(target) else { return nil }
        var best: [SIMD2<Int>]?
        for dy in -range...range { for dx in -range...range {
            let point = target &+ SIMD2(dx, dy)
            guard grid.contains(point) else { continue }
            var index = point.y * grid.width + point.x
            guard parents[index] >= 0 else { continue }
            var reversed: [SIMD2<Int>] = []
            while true {
                reversed.append(SIMD2(index % grid.width, index / grid.width))
                if parents[index] == index { break }
                index = parents[index]
            }
            if best == nil || reversed.count < best!.count { best = reversed.reversed() }
        } }
        return best
    }
}

struct NavigationLeg: Sendable {
    var map: String
    var path: [SIMD2<Int>]
    var portal: NavigationPortal?
}

enum NavigationFailure: Error, Equatable {
    case noPortalRoute, unreachable, missingMap(String), searchLimit
    var message: String {
        switch self {
        case .noPortalRoute: "No walking portal route is available."
        case .unreachable: "This destination cannot be reached on the available map."
        case .missingMap(let map): "Map data is unavailable for \(map)."
        case .searchLimit: "This route is too large to calculate. Choose a closer destination."
        }
    }
}

enum NavigationRouter {
    /// Breadth first over directed portal arrivals, not map names: two entrances
    /// to the same map can belong to disconnected walkable regions.
    static func route(from map: String, position: SIMD2<Int>, target: NavigationDestination,
                      portals: [NavigationPortal], load: @Sendable (String) async throws -> NavigationGrid) async throws -> [NavigationLeg] {
        let map = NavigationData.mapKey(map)
        let outgoing = Dictionary(grouping: portals, by: \.map)
        var canReach = Set([target.map])
        var changed = true
        while changed {
            changed = false
            for p in portals where canReach.contains(p.destinationMap) {
                if canReach.insert(p.map).inserted { changed = true }
            }
        }
        guard canReach.contains(map) else { throw NavigationFailure.noPortalRoute }
        struct State { var map: String; var position: SIMD2<Int>; var legs: [NavigationLeg] }
        var queue = [State(map: map, position: position, legs: [])], cursor = 0
        var visited: Set<String> = ["\(map):\(position.x):\(position.y)"]
        var grids: [String: NavigationGrid] = [:]
        var missing: String?
        while cursor < queue.count {
            try Task.checkCancellation()
            guard cursor < 512, grids.count < 96 else { throw NavigationFailure.searchLimit }
            let current = queue[cursor]; cursor += 1
            let grid: NavigationGrid
            if let cached = grids[current.map] { grid = cached }
            else {
                do { grid = try await load(current.map); grids[current.map] = grid }
                catch is CancellationError { throw CancellationError() }
                catch { missing = missing ?? current.map; continue }
            }
            let paths = grid.paths(from: current.position)
            if current.map == target.map {
                if let targetPoint = target.position {
                    if let path = paths.path(to: targetPoint, range: target.kind == .npc ? 2 : 0) {
                        return current.legs + [.init(map: current.map, path: path)]
                    }
                } else if grid.canWalk(current.position) {
                    return current.legs + [.init(map: current.map, path: [current.position])]
                }
            }
            for portal in outgoing[current.map] ?? [] where canReach.contains(portal.destinationMap) {
                let key = "\(portal.destinationMap):\(portal.destination.x):\(portal.destination.y)"
                guard !visited.contains(key), let path = paths.path(to: portal.position) else { continue }
                visited.insert(key)
                queue.append(State(map: portal.destinationMap, position: portal.destination,
                    legs: current.legs + [.init(map: current.map, path: path, portal: portal)]))
            }
        }
        if let missing { throw NavigationFailure.missingMap(missing) }
        throw NavigationFailure.unreachable
    }
}
