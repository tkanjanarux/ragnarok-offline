import Foundation
import Metal
import RagnarokConstants
import RagnarokCore
import RagnarokModels
import RagnarokPackets
import RagnarokRendering
import RagnarokShaders
import Testing
import simd
#if canImport(UIKit)
import UIKit
#endif
@testable import RagnarokGame

@Suite @MainActor struct PartyWorldBarTests {
    private func fixture() -> (PartyState, [UInt32: MapSceneMapObject], [UInt32: SIMD3<Float>]) {
        var party = PartyState(currentMap: "prontera")
        var roster = PACKET_ZC_GROUP_LIST()
        var objects: [UInt32: MapSceneMapObject] = [:]
        var positions: [UInt32: SIMD3<Float>] = [:]
        let identifiers: [UInt32] = [10, 11, 95_000_000, 12, 13, 14]
        for (index, identifier) in identifiers.enumerated() {
            var spawn = packet_spawn_unit()
            spawn.AID = identifier
            spawn.objecttype = identifier == 14 ? 5 : 0
            spawn.name = "Fixture"
            let object = MapObject(from: spawn)
            objects[identifier] = MapSceneMapObject(object: object, hp: -1, maxHp: -1,
                gridPosition: SIMD2(100 + index, 100), direction: .south, headDirection: .lookForward)
            positions[identifier] = SIMD3(Float(index % 3 - 1) * 5, Float(index / 3) * 5 - 2.5, 0)
            if identifier != 12 && identifier != 14 {
                var member = PACKET_ZC_GROUP_LIST_SUB()
                member.AID = identifier; member.GID = identifier + 100
                member.playerName = "Duplicate name"; member.mapName = "prontera.gat"
                roster.members.append(member)
            }
        }
        party.receive(roster, ownID: 10)
        for identifier: UInt32 in [10, 11, 95_000_000, 12, 14] {
            var packet = PACKET_ZC_NOTIFY_HP_TO_GROUPM()
            packet.AID = identifier; packet.hp = identifier == 95_000_000 ? 20 : 75; packet.maxhp = 100
            party.receive(packet, ownID: 10, now: .distantPast)
        }
        return (party, objects, positions)
    }

    private func bars(_ party: PartyState, _ objects: [UInt32: MapSceneMapObject],
                      _ positions: [UInt32: SIMD3<Float>]) -> [MapSceneRenderSnapshot.Bar] {
        PartyWorldBars.make(party: party, ownID: 10, mapName: "prontera.rsw", objects: objects,
                            worldPositions: positions, visibleIDs: Set(objects.keys))
    }

    @Test func membershipAndLifecycleNeverInventHealth() {
        var (party, objects, positions) = fixture()
        #expect(bars(party, objects, positions).count == 2)
        #expect(bars(party, objects, positions).allSatisfy { $0.screenSpace })
        positions[11] = SIMD3(1.25, 2.5, 0.75)
        #expect(bars(party, objects, positions).contains { $0.worldPosition == positions[11] })
        objects[11]?.effectState = MapEffectOptions(rawValue: StatusChangeOption.cloak.rawValue)
        #expect(bars(party, objects, positions).count == 1)
        objects[11]?.effectState = MapEffectOptions(rawValue: 0)
        objects[11]?.death = MapObjectDeath(startTime: .now, fadeDuration: nil)
        #expect(bars(party, objects, positions).count == 1)
        objects[11]?.death = nil
        var vanish = PACKET_ZC_NOTIFY_VANISH()
        vanish.gid = 11
        party.receive(vanish, ownID: 10)
        #expect(bars(party, objects, positions).count == 1)
        var health = PACKET_ZC_NOTIFY_HP_TO_GROUPM()
        health.AID = 11; health.hp = 60; health.maxhp = 100
        party.receive(health, ownID: 10)
        #expect(bars(party, objects, positions).count == 2)
        #expect(PartyWorldBars.make(party: party, ownID: 10, mapName: "geffen.rsw",
            objects: objects, worldPositions: positions, visibleIDs: Set(objects.keys)).isEmpty)
        objects.removeValue(forKey: 11)
        #expect(bars(party, objects, positions).count == 1)
        party.members[2].offline = true
        #expect(bars(party, objects, positions).isEmpty)
        party.members[2].offline = false
        health.AID = 95_000_000; health.hp = 0
        party.receive(health, ownID: 10)
        #expect(bars(party, objects, positions).isEmpty)
        health.hp = 80
        party.receive(health, ownID: 10)
        #expect(bars(party, objects, positions).count == 1)
        var warp = PACKET_ZC_NPCACK_MAPMOVE()
        warp.mapName = "prontera.gat"
        party.receive(warp, ownID: 10)
        #expect(bars(party, objects, positions).isEmpty)
        party.receive(health, ownID: 10)
        var leave = PACKET_ZC_DELETE_MEMBER_FROM_GROUP()
        leave.AID = 95_000_000
        party.receive(leave, ownID: 10)
        #expect(bars(party, objects, positions).isEmpty)
        party = PartyState()
        #expect(bars(party, objects, positions).isEmpty)
    }

    @Test func projectedSizeStaysReadableAcrossCameraAndZoom() throws {
        let viewport = MTLViewport(originX: 16, originY: 20, width: 1688, height: 780, znear: 0, zfar: 1)
        let model = matrix_rotate(matrix_identity_float4x4, -.pi, [1, 0, 0])
        let bar = MapSceneRenderSnapshot.Bar(vertices: BarMesh.partyHealth(hp: 75, maxHp: 100).vertices,
                                             worldPosition: .zero, screenSpace: true)
        for eye: SIMD3<Float> in [[0, 10, 20], [0, 16, 40], [15, 12, 25]] {
            let camera = RenderCamera(viewMatrix: lookAt(eye, .zero, [0, 1, 0]),
                projectionMatrix: perspective(0.5, Float(viewport.width / viewport.height), 0.1, 200))
            let projection = PartyBarProjection(viewport: viewport, pixelScale: 2, camera: camera, modelMatrix: model)
            let anchor = try #require(projection.screenPoint(.zero))
            let vertices = try #require(projection.vertices(for: bar))
            let right = SIMD3(camera.viewMatrix[0][0], camera.viewMatrix[1][0], camera.viewMatrix[2][0])
            let up = SIMD3(camera.viewMatrix[0][1], camera.viewMatrix[1][1], camera.viewMatrix[2][1])
            let pixels = vertices.map { vertex -> SIMD2<Float> in
                let position = right * vertex.position.x / 32 + up * vertex.position.y / 32
                let clip = camera.projectionMatrix * camera.viewMatrix * SIMD4(position, 1)
                return SIMD2(Float(viewport.originX) + (clip.x / clip.w + 1) * Float(viewport.width) / 2,
                             Float(viewport.originY) + (1 - clip.y / clip.w) * Float(viewport.height) / 2)
            }
            #expect(abs((pixels.map(\.x).max()! - pixels.map(\.x).min()!) - 120) < 0.01)
            #expect(abs(pixels.map(\.y).min()! - anchor.y - 16) < 0.01)
            #expect(abs(pixels.map(\.y).max()! - anchor.y - 28) < 0.01)
            #expect(projection.screenPoint(SIMD3(10000, 0, 0)) == nil)
        }
    }

    #if canImport(UIKit)
    @Test func simulatorMetalFixtureImages() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let renderer = try MapSceneRenderer(device: device, configuration: .default)
        let (party, objects, originalPositions) = fixture()
        for (name, size, eye, moved) in [
            ("landscape", CGSize(width: 844, height: 390), SIMD3<Float>(0, 14, 32), false),
            ("camera-zoom-movement", CGSize(width: 844, height: 390), SIMD3<Float>(12, 18, 25), true),
            ("portrait", CGSize(width: 390, height: 844), SIMD3<Float>(0, 22, 48), false)
        ] {
            var positions = originalPositions
            if moved { positions[11]! += SIMD3(1.25, -0.75, 0) }
            let scale: Float = 2
            let width = Int(size.width * CGFloat(scale)), height = Int(size.height * CGFloat(scale))
            let viewport = MTLViewport(size: CGSize(width: Double(width), height: Double(height)))
            let camera = RenderCamera(viewMatrix: lookAt(eye, .zero, [0, 1, 0]),
                projectionMatrix: perspective(0.6, Float(size.width / size.height), 0.1, 200), position: eye)
            var snapshot = MapSceneRenderSnapshot(fog: Fog())
            for identifier in objects.keys.sorted() {
                snapshot.spriteDrawables.append(SpriteDrawable(objectID: identifier,
                    worldPosition: positions[identifier]!, shadow: 1, isVisible: true,
                    layers: [.init(vertices: avatarVertices(), texture: try avatarTexture(device, monster: identifier == 14))]))
            }
            snapshot.bars = bars(party, objects, positions)
            snapshot.bars.append(.init(vertices: BarMesh.mesh(hp: 90, maxHp: 100, sp: 45, maxSp: 100, objectType: .pc).vertices,
                worldPosition: positions[10]! + [0, 0, -0.8]))
            #expect(snapshot.bars.count == 3)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = .renderTarget
            let color = try #require(device.makeTexture(descriptor: descriptor))
            descriptor.pixelFormat = .depth32Float; descriptor.storageMode = .private
            let depth = try #require(device.makeTexture(descriptor: descriptor))
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = color
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.10, green: 0.15, blue: 0.14, alpha: 1)
            pass.depthAttachment.texture = depth
            let command = try #require(queue.makeCommandBuffer())
            renderer.render(frame: RenderFrame(time: 0, commandBuffer: command, renderPassDescriptor: pass,
                views: [RenderView(viewport: viewport, camera: camera)], bounds: CGRect(origin: .zero, size: size)), snapshot: snapshot)
            command.commit(); command.waitUntilCompleted()
            #expect(command.error == nil)
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { color.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
            let projection = PartyBarProjection(viewport: viewport, pixelScale: scale, camera: camera,
                modelMatrix: matrix_rotate(matrix_identity_float4x4, -.pi, [1, 0, 0]))
            for identifier: UInt32 in [11, 95_000_000] {
                let foot = try #require(projection.screenPoint(positions[identifier]!))
                let row = Int(foot.y) + 20
                let start = Int(foot.x) - 55
                let colored = (start..<(start + 110)).filter { column in
                    let offset = (row * width + column) * 4
                    return identifier == 11 ? bytes[offset + 1] > 180 && bytes[offset + 2] < 80
                        : bytes[offset + 2] > 180 && bytes[offset + 1] < 80
                }.count
                #expect(colored > 15, "Missing HP pixels below feet: \(name) \(identifier)")
            }
            let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
            let cgImage = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            let format = UIGraphicsImageRendererFormat(); format.scale = 2
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
                let heading = "SIMULATOR FIXTURE • production Metal renderer\nSynthetic avatars + server packet fixtures • \(name)"
                (heading as NSString).draw(in: CGRect(x: 12, y: 12, width: size.width - 24, height: 55),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: UIColor.white])
                let labels: [UInt32: String] = [10: "Self (existing HP/SP)", 11: "Party 75/100", 95_000_000: "Companion 20/100",
                                               12: "Non-party: no bar", 13: "HP unknown: no bar", 14: "Monster: no party bar"]
                for (identifier, label) in labels {
                    guard let foot = projection.screenPoint(positions[identifier]!) else { continue }
                    (label as NSString).draw(in: CGRect(x: CGFloat(foot.x / scale) - 70, y: CGFloat(foot.y / scale) + 23, width: 140, height: 30),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.white])
                }
            }
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try #require(image.pngData()).write(to: directory.appendingPathComponent("party-bars-\(name).png"))
        }
    }

    private func avatarVertices() -> [SpriteVertex] {
        let corners: [(SIMD2<Float>, SIMD2<Float>)] = [([-20, 0], [0, 1]), ([20, 0], [1, 1]), ([-20, 80], [0, 0]),
            ([20, 0], [1, 1]), ([20, 80], [1, 0]), ([-20, 80], [0, 0])]
        return corners.map { SpriteVertex(position: $0.0, textureCoordinate: $0.1, color: [1, 1, 1, 1]) }
    }

    private func avatarTexture(_ device: any MTLDevice, monster: Bool) throws -> any MTLTexture {
        var pixels = [UInt8](repeating: 0, count: 20 * 40 * 4)
        func rectangle(_ left: Int, _ top: Int, _ width: Int, _ height: Int, _ color: [UInt8]) {
            for row in top..<(top + height) {
                for column in left..<(left + width) {
                    let offset = (row * 20 + column) * 4
                    pixels.replaceSubrange(offset..<(offset + 4), with: color)
                }
            }
        }
        if monster {
            rectangle(2, 24, 16, 16, [180, 90, 180, 255])
            rectangle(5, 28, 2, 3, [30, 20, 30, 255]); rectangle(13, 28, 2, 3, [30, 20, 30, 255])
        } else {
            rectangle(5, 2, 10, 12, [224, 180, 140, 255])
            rectangle(4, 1, 12, 5, [65, 55, 45, 255])
            rectangle(4, 15, 12, 14, [80, 130, 210, 255])
            rectangle(1, 15, 3, 17, [200, 200, 210, 255]); rectangle(16, 15, 3, 17, [200, 200, 210, 255])
            rectangle(5, 29, 4, 11, [100, 110, 140, 255]); rectangle(11, 29, 4, 11, [100, 110, 140, 255])
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 20, height: 40, mipmapped: false)
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        pixels.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, 20, 40), mipmapLevel: 0,
                                                  withBytes: $0.baseAddress!, bytesPerRow: 80) }
        return texture
    }
    #endif
}
