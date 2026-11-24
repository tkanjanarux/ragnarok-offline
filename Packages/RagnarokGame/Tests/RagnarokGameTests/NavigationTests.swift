import Foundation
import Metal
import RagnarokFileFormats
import RagnarokRendering
import RagnarokResources
import RagnarokScript
import simd
import SwiftUI
import Testing
#if canImport(UIKit)
import UIKit
#endif
@testable import RagnarokGame

@Suite @MainActor struct NavigationTests {
    static func grid(width: Int = 80, height: Int = 40, blocked: Set<SIMD2<Int>> = []) -> NavigationGrid {
        .init(width: width, height: height, walkable: (0..<height).flatMap { y in
            (0..<width).map { x in !blocked.contains(SIMD2(x, y)) }
        })
    }
    static let target = NavigationDestination(id: "npc:b:1", kind: .npc, name: "Guide", map: "b.gat", position: SIMD2(10, 10))
    static let portal = NavigationPortal(id: "a:1", map: "a", position: SIMD2(70, 20), destinationMap: "b", destination: SIMD2(2, 2))

    @Test func resourceColumnsAndUnknownCoordinates() throws {
        var data = NavigationData()
        try data.decode(Data("Navi_Map = {{'a','Town',5001,80,40}}".utf8), table: "Navi_Map")
        try data.decode(Data("Navi_Npc = {{'a',1,101,117,'Guide','',10,12},{'a',2,101,117,'Bad','',-1,12}}".utf8), table: "Navi_Npc")
        try data.decode(Data("Navi_Mob = {{'b',3,300,6554602,'Poring','PORING',1,0}}".utf8), table: "Navi_Mob")
        try data.decode(Data("Navi_Link = {{'a',4,200,45,'Portal','',70,20,'b',2,2},{'a',5,201,45,'Service','',1,1,'c',2,2}}".utf8), table: "Navi_Link")
        #expect(data.destinations.count == 3)
        #expect(data.portals.count == 1)
        #expect(data.destinations.first { $0.kind == .map }?.position == nil)
        #expect(data.destinations.first { $0.kind == .monster }?.position == nil)
        #expect(data.search("GUIDE", currentMap: "a").first?.position == SIMD2(10, 12))
        #expect(data.search("Poring", currentMap: "a").first?.map == "b")
        #expect(NavigationData.mapKey("A.RSW") == "a")
    }

    @Test func longRoutesObstaclesAndCornerClipping() {
        let wall = Set((0..<39).map { SIMD2(40, $0) })
        let paths = Self.grid(blocked: wall).paths(from: SIMD2(2, 2))
        let route = paths.path(to: SIMD2(75, 2))!
        #expect(route.count > 32)
        #expect(route.contains { $0.y == 39 })
        #expect(!route.contains { wall.contains($0) })
        let corner = Self.grid(width: 2, height: 2, blocked: [SIMD2(1, 0), SIMD2(0, 1)])
        #expect(corner.paths(from: .zero).path(to: SIMD2(1, 1)) == nil)
        #expect(paths.path(to: SIMD2(-1, 2)) == nil)
        let projection = MinimapProjection(width: 80, height: 40, size: 160)
        #expect(projection.point(SIMD2(0, 0)) == CGPoint(x: 0, y: 120))
        #expect(projection.point(SIMD2(80, 40)) == CGPoint(x: 160, y: 40))
    }

    @Test func portalTransitionsDirectedEdgesAndMissingMaps() async throws {
        let grid = Self.grid()
        let route = try await NavigationRouter.route(from: "a.rsw", position: SIMD2(2, 2), target: Self.target,
            portals: [Self.portal]) { _ in grid }
        #expect(route.map(\.map) == ["a", "b"])
        #expect(route[0].path.last == Self.portal.position)
        #expect(route[1].path.first == Self.portal.destination)
        #expect(route[1].path.last != nil)
        let final = route[1].path.last!
        #expect(max(abs(final.x - 10), abs(final.y - 10)) <= 2)
        do {
            _ = try await NavigationRouter.route(from: "b", position: SIMD2(2, 2),
                target: .init(id: "a", kind: .map, name: "A", map: "a"), portals: [Self.portal]) { _ in grid }
            Issue.record("Directed portal unexpectedly became bidirectional")
        } catch { #expect(error as? NavigationFailure == .noPortalRoute) }
        do {
            _ = try await NavigationRouter.route(from: "a", position: SIMD2(2, 2), target: Self.target,
                portals: [Self.portal]) { name in
                    if name == "b" { throw NavigationFailure.missingMap(name) }; return grid
                }
            Issue.record("Missing GAT silently accepted")
        } catch { #expect(error as? NavigationFailure == .missingMap("b")) }
        let wall = Self.grid(blocked: Set((0..<40).map { SIMD2(40, $0) }))
        do {
            _ = try await NavigationRouter.route(from: "a", position: SIMD2(2, 2), target: Self.target,
                portals: [Self.portal]) { _ in wall }
            Issue.record("Unreachable portal accepted")
        } catch { #expect(error as? NavigationFailure == .unreachable) }
        let spawn = NavigationDestination(id: "mob", kind: .monster, name: "Poring", map: "b")
        let arrived = try await NavigationRouter.route(from: "b", position: SIMD2(7, 9), target: spawn, portals: []) { _ in grid }
        #expect(arrived[0].path == [SIMD2(7, 9)]) // no invented monster coordinate
    }

    @Test func disconnectedEntrancesDoNotHideReachableAlternative() async throws {
        let a = Self.grid(width: 12, height: 12)
        let b = Self.grid(width: 12, height: 12, blocked: Set((0..<12).map { SIMD2(6, $0) }))
        let links = [NavigationPortal(id: "wrong", map: "a", position: SIMD2(2, 2), destinationMap: "b", destination: SIMD2(2, 2)),
                     NavigationPortal(id: "right", map: "a", position: SIMD2(8, 8), destinationMap: "b", destination: SIMD2(9, 9))]
        let route = try await NavigationRouter.route(from: "a", position: SIMD2(1, 1), target: Self.target,
            portals: links) { $0 == "a" ? a : b }
        #expect(route.first?.portal?.id == "right")
    }

    func awaitCalculation(_ state: NavigationState) async throws {
        for _ in 0..<200 {
            if state.status != .calculating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Navigation calculation did not finish")
    }

    @Test func movementWarpCancelAndLateResults() async throws {
        let state = NavigationState(), grid = Self.grid()
        let destination = NavigationDestination(id: "point", kind: .point, name: "Point", map: "a", position: SIMD2(70, 20))
        state.update(map: "a", position: SIMD2(2, 2), grid: grid, manager: .testing)
        #expect(state.target == nil && state.path.isEmpty) // opening never starts navigation
        state.begin(destination)
        try await awaitCalculation(state)
        #expect(state.status == .guiding)
        let next = state.path[5]
        state.update(map: "a", position: next, grid: grid, manager: .testing)
        #expect(state.path.first == next)
        state.update(map: "a", position: SIMD2(3, 30), grid: grid, manager: .testing)
        try await awaitCalculation(state)
        #expect(state.path.first == SIMD2(3, 30))
        state.mapChanging()
        #expect(state.path.isEmpty)
        state.update(map: "a", position: SIMD2(70, 20), grid: grid, manager: .testing)
        try await awaitCalculation(state)
        #expect(state.status == .arrived)
        state.begin(destination); state.cancel()
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.status == .idle && state.target == nil && state.path.isEmpty)
        state.begin(destination); state.mapChanging()
        state.update(map: "b", position: SIMD2(1, 1), grid: grid, manager: .testing)
        try await awaitCalculation(state)
        #expect(state.path.isEmpty)
        #expect(state.status == .failed(NavigationFailure.noPortalRoute.message))
        state.cancel()
    }

    #if canImport(UIKit)
    @Test func simulatorNavigationVisuals() async throws {
        let blocked = Set((0..<26).map { SIMD2(20, $0) })
        let grid = Self.grid(width: 40, height: 30, blocked: blocked)
        let state = NavigationState()
        state.update(map: "fixture", position: SIMD2(3, 3), grid: grid, manager: .testing)
        state.begin(.init(id: "fixture", kind: .point, name: "Fixture destination", map: "fixture", position: SIMD2(35, 5)))
        try await awaitCalculation(state)
        #expect(state.status == .guiding)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let mapImage = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { context in
            UIColor.darkGray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            let projection = MinimapProjection(width: 40, height: 30, size: 200)
            UIColor.gray.setFill()
            for point in blocked {
                let p = projection.point(point)
                context.fill(CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
            }
        }.cgImage!
        for (name, size) in [("portrait", CGSize(width: 390, height: 740)), ("landscape", CGSize(width: 740, height: 340))] {
            let content = VStack(spacing: 4) {
                Text("SIMULATOR FIXTURE • navigation UI\nSynthetic map and destination").font(.system(size: 12)).foregroundStyle(.white)
                NavigationContent(state: state, mapName: "fixture", width: 40, height: 30,
                    player: SIMD2(3, 3), mapImage: mapImage).background(.white)
            }.padding(12).frame(width: size.width, height: size.height).background(.black)
            let renderer = ImageRenderer(content: content); renderer.scale = 2
            let image = try #require(renderer.uiImage)
            let png = try #require(image.pngData())
            print("NAVIGATION_PNG \(name) \(png.base64EncodedString())")
        }
        // Actual production Metal tile renderer, using the same worldMarkers function as runtime.
        var bytes = Array("GRAT".utf8) + [UInt8(1), 2]
        for dimension: UInt32 in [40, 30] { bytes += (0..<4).map { UInt8(truncatingIfNeeded: dimension >> ($0 * 8)) } }
        for walkable in grid.walkable { bytes += [UInt8](repeating: 0, count: 16) + [walkable ? 0 : 1, 0, 0, 0] }
        let mapGrid = MapGrid(gat: try GAT(data: Data(bytes)))
        var snapshot = MapSceneRenderSnapshot(fog: Fog())
        snapshot.groundTiles = state.worldMarkers(mapName: "fixture", mapGrid: mapGrid)
        #expect(!snapshot.groundTiles.isEmpty)
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MapSceneRenderer(device: device, configuration: .default)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 800, height: 600, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = .renderTarget
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        descriptor.storageMode = .private; descriptor.pixelFormat = .depth32Float
        let depth = try #require(device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = texture; pass.depthAttachment.texture = depth
        let command = try #require(device.makeCommandQueue()?.makeCommandBuffer())
        let eye = SIMD3<Float>(20, 42, 24), center = SIMD3<Float>(20, 0, -15)
        let camera = RenderCamera(viewMatrix: lookAt(eye, center, [0, 1, 0]), projectionMatrix: perspective(0.9, 4 / 3, 0.1, 200), position: eye)
        renderer.render(frame: RenderFrame(time: 0, commandBuffer: command, renderPassDescriptor: pass,
            views: [RenderView(viewport: MTLViewport(size: CGSize(width: 800, height: 600)), camera: camera)],
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600)), snapshot: snapshot)
        command.commit(); command.waitUntilCompleted(); #expect(command.error == nil)
        var pixels = [UInt8](repeating: 0, count: 800 * 600 * 4)
        pixels.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: 3200, from: MTLRegionMake2D(0, 0, 800, 600), mipmapLevel: 0) }
        let yellow = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0 + 2] > 150 && pixels[$0 + 1] > 100 && pixels[$0] < 80 }.count
        #expect(yellow > 50, "Missing world navigation markers")
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let cg = try #require(CGImage(width: 800, height: 600, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 3200,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600), format: format).image { _ in
            UIImage(cgImage: cg).draw(at: .zero)
            ("SIMULATOR FIXTURE • production Metal navigation markers\nSynthetic GAT and destination • route around blocked cells" as NSString).draw(
                in: CGRect(x: 15, y: 15, width: 770, height: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.white])
        }
        print("NAVIGATION_PNG world-metal \(try #require(image.pngData()).base64EncodedString())")
    }
    #endif
}
