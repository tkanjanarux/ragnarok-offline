import Foundation
import Metal
import RagnarokConstants
import RagnarokCore
import RagnarokEffects
import RagnarokRendering
import RagnarokRenderAssets
import RagnarokResources
import simd
import Testing
@testable import RagnarokGame

private struct Pack: ResourceProvider {
    func contentsOfResource(at path: ResourcePath) async throws -> Data {
        let url = Bundle.module.resourceURL!.appendingPathComponent("ReferencePack").appendingPathComponent(path.description)
        return try Data(contentsOf: url)
    }
}

@MainActor
@Test func realGroundEffects() async throws {
    let manager = ResourceManager(resourceProvider: Pack())
    var audit: [String] = []
    await GroundEffectFiles.inspect(manager) { audit.append($0) }
    #expect(audit.count == 19)
    #expect(audit.allSatisfy { $0.hasSuffix("ไฟล์ครบ") }, "\(audit)")
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let renderer = try EffectRenderer(device: device, configuration: .default)
    let modelRenderer = try RSMModelRenderer(device: device, configuration: .default)
    let loader = EffectAssetLoader(resourceManager: manager)
    let camera = RenderCamera(viewMatrix: lookAt([0,8,16], [0,1,0], [0,1,0]), projectionMatrix: perspective(0.48,1,0.1,200))
    let matrix = matrix_rotate(matrix_identity_float4x4, -.pi, [1,0,0])
    func pixels(_ draw: (any MTLRenderCommandEncoder) -> Void) throws -> Int {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 192, height: 192, mipmapped: false)
        d.usage = .renderTarget
        d.storageMode = .shared
        let color = try #require(device.makeTexture(descriptor: d))
        d.pixelFormat = .depth32Float
        d.storageMode = .private
        let depth = try #require(device.makeTexture(descriptor: d))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        let command = try #require(queue.makeCommandBuffer())
        let encoder = try #require(command.makeRenderCommandEncoder(descriptor: pass))
        draw(encoder)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        #expect(command.error == nil)
        var data = Array(repeating: UInt8(0),count: 192*192*4)
        data.withUnsafeMutableBytes { color.getBytes($0.baseAddress!, bytesPerRow: 192*4, from: MTLRegionMake2D(0,0,192,192), mipmapLevel: 0) }
        return stride(from: 0,to: data.count,by: 4).filter { max(data[$0],data[$0+1],data[$0+2]) > 5 }.count
    }
    for id: EffectID in [.ef_firepillaron,.ef_firepillar,.ef_firepillarbomb,.ef_firewall,.ef_glasswall2,.ef_bottom_sanc,.ef_pneuma,.ef_quagmire,.ef_stormgust,.ef_lord,.ef_readyportal2,.ef_portal2] {
        let asset = try await loader.loadAssetGroup(with: EffectTable.definitions(for: id))
        let group = EffectRenderResourceGroup(device: device, assetGroup: asset, creationTime: 0, worldPosition: .zero)
        var visible = 0
        for t in [0.1,0.35,0.7,1.1,1.5] {
            visible = max(visible,try pixels { renderer.render(resourceGroup: group, atTime: t, fog: Fog(), modelMatrix: matrix, camera: camera, renderCommandEncoder: $0) })
        }
        #expect(visible > 4, "\(id) colored pixels: \(visible)")
        if id == .ef_firepillaron {
            #expect(!group.isExpired(atTime: 29))
            #expect(try pixels { renderer.render(resourceGroup: group, atTime: 29, fog: Fog(), modelMatrix: matrix, camera: camera, renderCommandEncoder: $0) } > 4)
        }
    }
    for variant in GroundTrapModels.variants.values {
        let name = GroundTrapModels.name(for: variant)
        let model = try await manager.model(forName: name)
        let images = await manager.textureImages(forNames: model.textureNames, removesMagentaPixels: true)
        let asset = RSMModelRenderAsset(name: name, rsm: model.rsm, instance: .init(position: .zero, rotation: .zero, scale: .init(repeating: 0.2)), textureImages: images)
        let resource = RSMModelRenderResource(device: device, asset: asset, light: .preview)
        #expect(try pixels { modelRenderer.render(resources: [resource], atTime: 0, fog: Fog(), modelMatrix: matrix, camera: camera, renderCommandEncoder: $0) } > 1)
    }
}
