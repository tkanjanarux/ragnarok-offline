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
    typealias Status = NavigationGuidance.Status
    private(set) var data = NavigationData()
    private(set) var loadingData = false
    private(set) var loadedData = false
    let guidance = NavigationGuidance()
    var target: NavigationDestination? { guidance.target }
    var status: Status { guidance.status }
    var legs: [NavigationLeg] { guidance.legs }
    var map: String { guidance.map }
    var position: SIMD2<Int> { guidance.position }
    var path: [SIMD2<Int>] { guidance.path }
    var nextPortal: NavigationPortal? { guidance.nextPortal }
    @ObservationIgnored private var grid: NavigationGrid?
    @ObservationIgnored private let maps = NavigationMapStore()
    @ObservationIgnored private var dataLoading: Task<NavigationData, Never>?

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

    func begin(_ destination: NavigationDestination) { guidance.begin(destination, portals: data.portals) }
    func cancel() { guidance.cancel() }
    func mapChanging() { grid = nil; guidance.mapChanging() }

    func update(map name: String, position: SIMD2<Int>, mapGrid: MapGrid, manager: ResourceManager) {
        if map != NavigationData.mapKey(name) || grid == nil { grid = NavigationGrid(mapGrid: mapGrid) }
        update(map: name, position: position, grid: grid!, manager: manager)
    }

    func update(map name: String, position: SIMD2<Int>, grid: NavigationGrid, manager: ResourceManager) {
        let store = maps
        guidance.update(map: name, position: position, grid: grid, portals: data.portals) { name in
            try await store.grid(name, manager: manager)
        }
    }

    func worldMarkers(mapName: String, mapGrid: MapGrid) -> [MapSceneRenderSnapshot.NavigationArrow] {
        guard NavigationData.mapKey(mapName) == map else { return [] }
        return guidance.markers.compactMap { marker in
            guard mapGrid.contains(marker.position) else { return nil }
            let cell = mapGrid[marker.position]
            return .init(marker: marker, altitudes: [cell.bottomLeftAltitude, cell.bottomRightAltitude,
                                                    cell.topLeftAltitude, cell.topRightAltitude])
        }
    }
}
