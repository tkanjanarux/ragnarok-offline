import Foundation
import Observation
import RagnarokScript

struct NavigationBreadcrumb: Equatable, Sendable, Identifiable {
    struct ID: Hashable, Sendable { let route: Int; let index: Int }
    let id: ID
    let position: SIMD2<Int>
    let direction: SIMD2<Int>
}

/// Presentation-independent route lifecycle, also exercised by the portable tests.
@MainActor @Observable
final class NavigationGuidance {
    enum Status: Equatable { case idle, calculating, guiding, arrived, failed(String) }
    typealias GridLoader = @Sendable (String) async throws -> NavigationGrid
    typealias Router = @Sendable (String, SIMD2<Int>, NavigationDestination, [NavigationPortal], @escaping GridLoader) async throws -> [NavigationLeg]
    private(set) var target: NavigationDestination?
    private(set) var status = Status.idle
    private(set) var legs: [NavigationLeg] = []
    private(set) var map = ""
    private(set) var position = SIMD2<Int>.zero
    private(set) var cursor = 0
    private(set) var markers: [NavigationBreadcrumb] = []
    private(set) var calculationCount = 0
    @ObservationIgnored private var grid: NavigationGrid?
    @ObservationIgnored private var portals: [NavigationPortal] = []
    @ObservationIgnored private var loader: GridLoader?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var routeMarkers: [NavigationBreadcrumb] = []
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let router: Router

    init(delay: Duration = .milliseconds(180), router: @escaping Router = { map, start, target, portals, loader in
        try await NavigationRouter.route(from: map, position: start, target: target, portals: portals, load: loader)
    }) { self.delay = delay; self.router = router }

    var path: [SIMD2<Int>] { legs.first?.map == map ? Array(legs[0].path.dropFirst(cursor)) : [] }
    var nextPortal: NavigationPortal? { legs.first?.map == map ? legs.first?.portal : nil }

    func begin(_ destination: NavigationDestination, portals: [NavigationPortal]? = nil) {
        if let portals { self.portals = portals }
        if target == destination, legs.first?.map == map {
            invalidate(); schedule(debounced: false)
        } else {
            cancel(); target = destination; schedule(debounced: false)
        }
    }
    func cancel() {
        invalidate(); target = nil; clearRoute(); status = .idle
    }
    func mapChanging() {
        invalidate(); clearRoute(); grid = nil; map = ""
        status = target == nil ? .idle : .calculating
    }
    private func invalidate() { generation += 1; task?.cancel(); task = nil }
    private func clearRoute() { legs = []; cursor = 0; routeMarkers = []; markers = [] }

    func update(map: String, position: SIMD2<Int>, grid: NavigationGrid,
                portals: [NavigationPortal], loader: @escaping GridLoader) {
        let key = NavigationData.mapKey(map), changed = key != self.map, moved = position != self.position
        if changed { mapChanging() }
        self.map = key; self.position = position; self.grid = grid; self.portals = portals; self.loader = loader
        guard let target else { return }
        if target.map == key, target.position == nil {
            invalidate(); clearRoute(); status = .arrived; return
        }
        if !changed, !moved, !legs.isEmpty { return }
        if advance() {
            // Returning to the valid path makes an off-route computation obsolete.
            if task != nil { invalidate() }
            return
        }
        if changed || moved || (status == .calculating && task == nil) { schedule(debounced: !changed) }
    }

    @discardableResult private func advance() -> Bool {
        guard legs.first?.map == map,
              let index = legs[0].path.indices.dropFirst(cursor).first(where: { legs[0].path[$0] == position }) else { return false }
        cursor = index
        status = index == legs[0].path.count - 1 && nextPortal == nil ? .arrived : .guiding
        let visible = status == .arrived ? [] : routeMarkers.filter { $0.id.index >= index && $0.id.index < index + 100 }
        if visible != markers { markers = visible }
        return true
    }

    private func schedule(debounced: Bool) {
        // A single pending task reads the newest position after the delay. Continuous
        // off-route movement cannot starve the calculation or start one per frame.
        guard task == nil, target != nil, grid != nil, loader != nil, !map.isEmpty else { return }
        generation += 1; let token = generation
        status = .calculating // Keep the last same-map route visible until replacement.
        task = Task { [weak self] in
            guard let self else { return }
            if debounced { do { try await Task.sleep(for: delay) } catch { return } }
            guard !Task.isCancelled, token == generation, let target, let grid, let loader else { return }
            let startMap = map, start = position, links = portals, route = router
            calculationCount += 1
            let worker = Task.detached {
                try await route(startMap, start, target, links) { name in
                    if name == startMap { return grid }
                    return try await loader(name)
                }
            }
            let result = await withTaskCancellationHandler { await worker.result } onCancel: { worker.cancel() }
            guard !Task.isCancelled, token == generation, startMap == map, self.target == target else { return }
            task = nil
            switch result {
            case .success(let proposed):
                // Never flash a route whose start is behind the latest player position.
                guard let first = proposed.first, first.map == map, first.path.contains(position) else {
                    if start == position { clearRoute(); status = .failed("Unable to load this route.") }
                    else { schedule(debounced: true) }
                    return
                }
                revision += 1
                let breadcrumbs = first.path.indices.compactMap { index -> NavigationBreadcrumb? in
                    guard index % 3 == 0, index + 1 < first.path.count else { return nil }
                    return .init(id: .init(route: revision, index: index), position: first.path[index],
                                 direction: first.path[index + 1] &- first.path[index])
                }
                legs = proposed; cursor = 0; routeMarkers = breadcrumbs
                _ = advance() // one MainActor turn: publish a complete valid route
            case .failure(let error):
                if start != position { schedule(debounced: true) }
                else { clearRoute(); status = .failed((error as? NavigationFailure)?.message ?? "Unable to load this route.") }
            }
        }
    }
}
