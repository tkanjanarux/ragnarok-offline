//
//  NavigationArrowRenderer.swift
//  RagnarokGame
//
//  Created by Leon Li on 2026/3/23.
//

import Foundation
import Metal
import QuartzCore
import RagnarokRendering
import RagnarokShaders
import simd

final class NavigationArrowRenderer {
    let device: any MTLDevice

    private var fallbackTexture: (any MTLTexture)?
    private let renderPipelineState: any MTLRenderPipelineState
    private let depthStencilState: (any MTLDepthStencilState)?

    init(device: any MTLDevice, configuration: RenderConfiguration) throws {
        self.device = device

        let library = RagnarokShadersLibrary(device)!

        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "navigationVertexShader")
        renderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "navigationFragmentShader")
        renderPipelineDescriptor.maxVertexAmplificationCount = configuration.amplificationCount
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = configuration.colorPixelFormat
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        renderPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        renderPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        renderPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        renderPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        renderPipelineDescriptor.depthAttachmentPixelFormat = configuration.depthStencilPixelFormat
        renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)

        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = configuration.depthCompareFunction
        depthStencilDescriptor.isDepthWriteEnabled = false
        depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        fallbackTexture = device.makeTexture(descriptor: textureDescriptor)
        fallbackTexture?.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: [UInt8](repeating: 255, count: 4), bytesPerRow: 4)
    }

    private var cached: [MapSceneRenderSnapshot.NavigationArrow] = []
    private var vertices: (any MTLBuffer)?
    private var uvs: (any MTLBuffer)?
    private var vertexCount = 0

    func render(arrows: [MapSceneRenderSnapshot.NavigationArrow], texture: (any MTLTexture)?, fog: Fog,
                modelMatrix: simd_float4x4, camera: RenderCamera, renderCommandEncoder encoder: any MTLRenderCommandEncoder) {
        if cached != arrows {
            cached = arrows
            let points = arrows.flatMap { arrow in
                NavigationArrowGeometry.points(direction: arrow.marker.direction).map {
                    TileVertex(position: NavigationArrowGeometry.position($0, tile: arrow.marker.position, altitudes: arrow.altitudes))
                }
            }
            let coordinates = arrows.flatMap { _ in NavigationArrowGeometry.uv }
            vertexCount = points.count
            vertices = points.isEmpty ? nil : points.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }
            uvs = coordinates.isEmpty ? nil : coordinates.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }
        }
        guard vertexCount > 0, let vertices, let uvs else { return }
        var vertexUniforms = TileVertexUniforms(modelMatrix: modelMatrix, viewMatrix: camera.viewMatrix, projectionMatrix: camera.projectionMatrix)
        var fragmentUniforms = TileFragmentUniforms(color: [1, 0.86, 0.1, 0.95], fogUse: fog.isEnabled ? 1 : 0,
            fogNear: fog.near, fogFar: fog.far, fogColor: fog.color)
        var textured: Int32 = texture == nil ? 0 : 1
        encoder.setRenderPipelineState(renderPipelineState)
        encoder.setDepthStencilState(depthStencilState)
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&vertexUniforms, length: MemoryLayout<TileVertexUniforms>.stride, index: 1)
        encoder.setVertexBuffer(uvs, offset: 0, index: 2)
        encoder.setFragmentBytes(&fragmentUniforms, length: MemoryLayout<TileFragmentUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&textured, length: MemoryLayout<Int32>.stride, index: 1)
        encoder.setFragmentTexture(texture ?? fallbackTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
    }
}
