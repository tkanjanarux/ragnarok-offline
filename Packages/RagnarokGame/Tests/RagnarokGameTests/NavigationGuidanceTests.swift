import Foundation
import RagnarokScript
import Testing
@testable import RagnarokGame

private actor RouteGate {
    struct Request: Sendable { let map: String; let start: SIMD2<Int> }
    private(set) var requests: [Request] = []
    var continuations: [Int: CheckedContinuation<[NavigationLeg], any Error>] = [:]
    func run(map: String, start: SIMD2<Int>) async throws -> [NavigationLeg] {
        let id = requests.count; requests.append(.init(map: map, start: start))
        return try await withCheckedThrowingContinuation { continuations[id] = $0 }
    }
    func finish(_ id: Int, path: [SIMD2<Int>]) {
        continuations.removeValue(forKey: id)?.resume(returning: [.init(map: requests[id].map, path: path, portal: nil)])
    }
}

@Suite @MainActor struct NavigationGuidanceTests {
    static let grid = NavigationGrid(width: 100, height: 100, walkable: Array(repeating: true, count: 10000))
    static let line = (0...40).map { SIMD2($0, 10) }
    static let destination = NavigationDestination(id: "point", kind: .point, name: "End", map: "a", position: SIMD2(40, 10))
    func update(_ state: NavigationGuidance, _ p: SIMD2<Int>, map: String = "a") {
        let grid = Self.grid
        state.update(map: map, position: p, grid: grid, portals: []) { _ in grid }
    }
    func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Timed out waiting for route lifecycle")
    }
    private func prepared(_ gate: RouteGate) async throws -> NavigationGuidance {
        let state = NavigationGuidance(delay: .milliseconds(30)) { map, start, _, _, _ in try await gate.run(map: map, start: start) }
        update(state, Self.line[0]); state.begin(Self.destination)
        try await wait { await gate.requests.count == 1 }
        await gate.finish(0, path: Self.line)
        try await wait { state.status == .guiding }
        return state
    }

    @Test func walkingKeepsMarkerPhaseIdentityAndAvoidsRecalculation() async throws {
        let gate = RouteGate(), state = try await prepared(gate)
        let original = state.markers
        for index in 1...12 {
            update(state, Self.line[index])
            #expect(state.markers == original.filter { $0.id.index >= index })
            #expect(state.path.first == Self.line[index])
            #expect(state.legs[0].path == Self.line) // route is immutable while progressing
        }
        #expect(state.calculationCount == 1)
        #expect(await gate.requests.count == 1)
        state.cancel()
    }

    @Test func pendingRerouteKeepsMarkersAndCoalescesMovement() async throws {
        let gate = RouteGate(), state = try await prepared(gate)
        let markers = state.markers
        for x in 1...15 { update(state, SIMD2(x, 12)) }
        #expect(state.status == .calculating)
        #expect(state.markers == markers)
        #expect(state.path == Self.line)
        try await wait { await gate.requests.count == 2 }
        #expect(await gate.requests[1].start == SIMD2(15, 12))
        #expect(state.calculationCount == 2)
        let replacement = (15...40).map { SIMD2($0, 12) }
        await gate.finish(1, path: replacement)
        try await wait { state.status == .guiding }
        #expect(state.path == replacement)
        #expect(state.markers.first?.id.route != markers.first?.id.route)
        state.cancel()
    }

    @Test func explicitRecalculateSameTargetRetainsValidRoute() async throws {
        let gate = RouteGate(), state = try await prepared(gate)
        let markers = state.markers
        state.begin(Self.destination)
        #expect(state.status == .calculating && state.markers == markers)
        try await wait { await gate.requests.count == 2 }
        await gate.finish(1, path: Self.line)
        try await wait { state.status == .guiding }
        state.cancel()
    }

    @Test func returnToRouteDiscardsLateReroute() async throws {
        let gate = RouteGate(), state = try await prepared(gate)
        update(state, SIMD2(2, 12)); try await wait { await gate.requests.count == 2 }
        update(state, Self.line[3])
        let stable = state.markers
        await gate.finish(1, path: [Self.line[3], SIMD2(3, 20)])
        try await Task.sleep(for: .milliseconds(30))
        #expect(state.markers == stable)
        #expect(state.legs[0].path == Self.line)
        state.cancel()
    }

    @Test func cancelDestinationAndWarpRejectStaleAsyncResults() async throws {
        for action in 0...2 {
            let gate = RouteGate(), state = try await prepared(gate)
            update(state, SIMD2(2, 12)); try await wait { await gate.requests.count == 2 }
            if action == 0 { state.cancel() }
            if action == 1 { state.begin(.init(id: "other", kind: .point, name: "Other", map: "a", position: SIMD2(5, 80))) }
            if action == 2 { state.mapChanging() }
            #expect(state.markers.isEmpty && state.path.isEmpty)
            await gate.finish(1, path: [SIMD2(2, 12), SIMD2(3, 12)])
            try await Task.sleep(for: .milliseconds(30))
            #expect(state.markers.isEmpty && state.path.isEmpty)
            if action == 1 {
                try await wait { await gate.requests.count == 3 }
                state.cancel(); await gate.finish(2, path: [SIMD2(2,12)])
            }
            state.cancel()
        }
    }

    @Test func warpPublishesOnlyNewMapAndArrivalClearsArrows() async throws {
        let gate = RouteGate(), state = try await prepared(gate)
        update(state, .zero, map: "b")
        #expect(state.markers.isEmpty)
        try await wait { await gate.requests.count == 2 }
        await gate.finish(1, path: [.zero, SIMD2(0,1), SIMD2(0,2)])
        try await wait { state.status == .guiding }
        #expect(state.map == "b")
        update(state, SIMD2(0,2), map: "b")
        #expect(state.status == .arrived && state.markers.isEmpty)
        state.cancel()
    }

    @Test func catalogueLoadedWhileStationaryIsUsedAtBegin() async throws {
        let state = NavigationGuidance()
        update(state, SIMD2(1,1)) // scene was attached before navigation data loaded
        let portal = NavigationPortal(id: "a-b", map: "a", position: SIMD2(4,4), destinationMap: "b", destination: SIMD2(1,1))
        state.begin(.init(id: "b", kind: .map, name: "B", map: "b"), portals: [portal])
        try await wait { state.status != .calculating }
        #expect(state.status == .guiding && state.nextPortal?.id == "a-b")
        state.cancel()
    }

    @Test func allEightDirectionsMatchGroundAxesAndTextureTop() {
        for x in -1...1 { for y in -1...1 where x != 0 || y != 0 {
            let points = NavigationArrowGeometry.points(direction: SIMD2(x,y))
            let top = (points[2] + points[4]) / 2 - SIMD2<Float>(repeating: 0.5)
            #expect(top.x * Float(x) + top.y * Float(y) > 0)
            #expect(abs(top.x * Float(y) - top.y * Float(x)) < 0.0001)
            #expect(NavigationArrowGeometry.uv[2].y == 0)
        } }
        let p = NavigationArrowGeometry.position([0.75,0.25], tile: [4,8], altitudes: [0,1,2,3])
        #expect(abs(p.y + 1.37) < 0.001)
        #expect(p.x == 4.75 && p.z == 8.25)
    }

    @Test func titlebarHitRegionsNeverOverlapContentOrEachOther() {
        // Panel families: compact Bank, portrait Settings, wide Guild, tiny viewport.
        for size: CGSize in [CGSize(width:280,height:200), CGSize(width:320,height:430), CGSize(width:600,height:580), CGSize(width:160,height:90)] {
            for scale: CGFloat in [1,0.75,0.4] {
                for close: CGFloat in [28,44] {
                    let chrome = PanelChromeLayout(width:size.width, height:size.height, scale:scale, requestedHeight:close == 28 ? 28 : 17, closeSize:close)
                    #expect(chrome.close.minX == chrome.drag.maxX)
                    #expect(chrome.close.maxX == size.width)
                    #expect(chrome.close.maxY <= chrome.headerHeight)
                    #expect(chrome.drag.maxY <= chrome.headerHeight)
                    #expect(chrome.headerHeight <= size.height)
                    #expect(chrome.close.width * scale >= min(close, size.width * scale))
                }
            }
        }
    }
    @Test func sharedPanelsPreserveFixedContentAndFitSafeViewport() {
        let panels: [CGSize] = [.init(width:723,height:540), .init(width:381,height:466),
            .init(width:320,height:278), .init(width:300,height:132), .init(width:356,height:420),
            .init(width:500,height:650), .init(width:280,height:200)]
        for panel in panels {
            for viewport: CGSize in [.init(width:288,height:530), .init(width:620,height:280), .init(width:800,height:740)] {
                for header: CGFloat in [17,28] {
                    let close: CGFloat = header == 17 ? 44 : 28
                    let layout = PanelWindowLayout(width:panel.width, height:panel.height, available:viewport, requestedHeader:header, closeSize:close)
                    #expect(layout.contentHeight == panel.height - header)
                    #expect(layout.height * layout.scale <= viewport.height + 0.001)
                    #expect(panel.width * layout.scale <= viewport.width + 0.001)
                    #expect(abs(layout.chrome.close.height * layout.scale - close) < 0.001)
                    #expect(layout.chrome.headerHeight + layout.contentHeight <= layout.height + 0.001)
                }
            }
        }
    }

}
