import Foundation
import Observation
import RagnarokFileFormats
import RagnarokResources
import RagnarokScript

extension NavigationGrid {
    init(mapGrid: MapGrid) {
        let width = mapGrid.width, height = mapGrid.height
        self.width = width; self.height = height
        walkable = (0..<height).flatMap { y in (0..<width).map { x in mapGrid[SIMD2(x, y)].isWalkable } }
    }
}

actor NavigationMapStore {
    private var grids: [String: NavigationGrid] = [:]
    func grid(_ name: String, manager: ResourceManager) async throws -> NavigationGrid {
        if let cached = grids[name] { return cached }
        let bytes = try await manager.contentsOfResource(at: ["data", name + ".gat"])
        // Bound dimensions before the shared GAT decoder allocates or indexes cells.
        let header = [UInt8](bytes.prefix(14))
        guard header.count == 14 else { throw NavigationFailure.missingMap(name) }
        func integer(_ start: Int) -> Int { (0..<4).reduce(0) { $0 | Int(header[start + $1]) << ($1 * 8) } }
        let width = integer(6), height = integer(10)
        guard width > 0, height > 0, width <= 1024, height <= 1024,
              bytes.count >= 14 + width * height * 20 else { throw NavigationFailure.missingMap(name) }
        let gat = try GAT(data: bytes)
        let grid = NavigationGrid(width: width, height: height, walkable: gat.tiles.map(\.isWalkable))
        if grids.count >= 96 { grids.removeAll() }
        grids[name] = grid
        return grid
    }
}

@MainActor @Observable
final class NavigationState {
    enum Status: Equatable { case idle, calculating, guiding, arrived, failed(String) }
    private(set) var data = NavigationData()
    private(set) var loadingData = false
    private(set) var loadedData = false
    private(set) var target: NavigationDestination?
    private(set) var status = Status.idle
    private(set) var legs: [NavigationLeg] = []
    private(set) var map = ""
    private(set) var position = SIMD2<Int>.zero
    @ObservationIgnored private var grid: NavigationGrid?
    @ObservationIgnored private var manager: ResourceManager?
    @ObservationIgnored private let maps = NavigationMapStore()
    @ObservationIgnored private var calculation: Task<Void, Never>?
    @ObservationIgnored private var dataLoading: Task<NavigationData, Never>?
    @ObservationIgnored private var generation = 0

    var path: [SIMD2<Int>] { legs.first?.map == map ? legs.first!.path : [] }
    var nextPortal: NavigationPortal? { legs.first?.map == map ? legs.first?.portal : nil }
    var message: String {
        switch status {
        case .idle: "Choose a destination. Walk along the highlighted route."
        case .calculating: "Finding a walking route…"
        case .guiding:
            if let portal = nextPortal { "Portal to \(portal.destinationMap) · \(portal.position.x), \(portal.position.y)" }
            else { "Follow the highlighted route to your destination." }
        case .arrived: target?.kind == .monster ? "You are in the spawn map. Explore to find monsters." : "Destination reached."
        case .failed(let reason): reason
        }
    }

    func loadData(using manager: ResourceManager) async {
        guard !loadedData else { return }
        let task: Task<NavigationData, Never>
        if let existing = dataLoading { task = existing }
        else {
            task = Task.detached { await manager.navigationData() }
            dataLoading = task; loadingData = true
        }
        // The catalogue belongs to the session, not a particular map view.
        // A warp canceling the old view task must not abandon the new view's load.
        data = await task.value
        loadedData = true; loadingData = false; dataLoading = nil
    }

    func begin(_ destination: NavigationDestination) {
        cancel()
        target = destination
        calculate()
    }

    func cancel() {
        generation += 1; calculation?.cancel(); calculation = nil
        target = nil; legs = []; status = .idle
    }

    func mapChanging() {
        generation += 1; calculation?.cancel(); calculation = nil
        legs = []; grid = nil; map = ""
        status = target == nil ? .idle : .calculating
    }

    func update(map name: String, position: SIMD2<Int>, mapGrid: MapGrid, manager: ResourceManager) {
        let key = NavigationData.mapKey(name)
        if map != key || grid == nil { grid = NavigationGrid(mapGrid: mapGrid) }
        update(map: key, position: position, grid: grid!, manager: manager)
    }

    func update(map name: String, position: SIMD2<Int>, grid: NavigationGrid, manager: ResourceManager) {
        let key = NavigationData.mapKey(name)
        let changedMap = key != map
        let moved = position != self.position
        if changedMap { mapChanging() }
        self.map = key; self.position = position; self.grid = grid; self.manager = manager
        guard let target else { return }
        if target.map == key, target.position == nil {
            calculation?.cancel(); calculation = nil; generation += 1
            legs = []; status = .arrived; return
        }
        if !changedMap, !path.isEmpty, let index = path.firstIndex(of: position) {
            if index > 0 { legs[0].path.removeFirst(index) }
            status = path.count == 1 && nextPortal == nil ? .arrived : .guiding
            return
        }
        if changedMap || moved || status == .calculating { calculate() }
    }

    private func calculate() {
        guard calculation == nil, let target, let manager, let grid, !map.isEmpty else { return }
        let startMap = map, start = position, portals = data.portals, store = maps
        generation += 1; let token = generation
        legs = []; status = .calculating
        // GAT search never blocks rendering or user input. Generation checks prevent
        // canceled destinations/old-map results from resurrecting route markers.
        calculation = Task {
            let worker = Task.detached {
                try await NavigationRouter.route(from: startMap, position: start, target: target, portals: portals) { name in
                    if name == startMap { return grid }
                    return try await store.grid(name, manager: manager)
                }
            }
            let result = await withTaskCancellationHandler {
                await worker.result
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled, token == self.generation else { return }
            self.calculation = nil
            switch result {
            case .success(let route):
                self.legs = route
                if let index = self.path.firstIndex(of: self.position) {
                    self.legs[0].path.removeFirst(index)
                    self.status = self.path.count == 1 && self.nextPortal == nil ? .arrived : .guiding
                } else { self.calculate() }
            case .failure(let error):
                if start != self.position { self.calculate() }
                else { self.status = .failed((error as? NavigationFailure)?.message ?? "Unable to load this route.") }
            }
        }
    }

    func worldMarkers(mapName: String, mapGrid: MapGrid) -> [MapSceneRenderSnapshot.TileSelector] {
        guard NavigationData.mapKey(mapName) == map, status == .guiding else { return [] }
        // Bound draw calls while keeping the near-player guidance visible.
        return path.prefix(100).enumerated().compactMap { index, point in
            guard index % 3 == 0, mapGrid.contains(point) else { return nil }
            return .init(position: point, cell: mapGrid[point], color: [1, 0.78, 0.08, 0.9])
        }
    }
}
