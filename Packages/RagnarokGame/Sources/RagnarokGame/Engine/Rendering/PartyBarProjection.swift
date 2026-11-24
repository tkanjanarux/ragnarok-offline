import Metal
import RagnarokRendering
import RagnarokShaders
import simd

struct PartyBarProjection {
    let viewport: MTLViewport
    let pixelScale: Float
    let camera: RenderCamera
    let modelMatrix: simd_float4x4

    func anchor(_ position: SIMD3<Float>) -> SIMD4<Float>? {
        let clip = camera.projectionMatrix * camera.viewMatrix * modelMatrix
            * SIMD4<Float>(position.x, -position.z, position.y, 1)
        guard viewport.width > 0, viewport.height > 0, pixelScale > 0,
              clip.w > 0, clip.z >= 0, clip.z <= clip.w,
              abs(clip.x) <= clip.w, abs(clip.y) <= clip.w else { return nil }
        return clip
    }

    func screenPoint(_ position: SIMD3<Float>) -> SIMD2<Float>? {
        guard let clip = anchor(position) else { return nil }
        return SIMD2(
            Float(viewport.originX) + (clip.x / clip.w + 1) * Float(viewport.width) / 2,
            Float(viewport.originY) + (1 - clip.y / clip.w) * Float(viewport.height) / 2
        )
    }

    func vertices(for bar: MapSceneRenderSnapshot.Bar) -> [SpriteVertex]? {
        guard let clip = anchor(bar.worldPosition),
              camera.projectionMatrix[0][0] != 0, camera.projectionMatrix[1][1] != 0 else { return nil }
        let scale = SIMD2<Float>(
            64 * clip.w * pixelScale / (Float(viewport.width) * camera.projectionMatrix[0][0]),
            64 * clip.w * pixelScale / (Float(viewport.height) * camera.projectionMatrix[1][1])
        )
        return bar.vertices.map { vertex in
            SpriteVertex(position: vertex.position * scale,
                         textureCoordinate: vertex.textureCoordinate, color: vertex.color)
        }
    }
}
