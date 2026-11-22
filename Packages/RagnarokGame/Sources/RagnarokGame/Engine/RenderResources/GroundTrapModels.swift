import Metal
import RagnarokCore
import RagnarokRenderAssets
import RagnarokRendering
import RagnarokResources

@MainActor
final class GroundTrapModels {
    static let variants: [Int32: String] = [
        143: "03_3", 144: "02", 145: "01", 147: "03", 148: "03_6",
        149: "03_4", 150: "03_5", 151: "03_2", 152: "04", 153: "05",
    ]

    static func name(for variant: String) -> String { K2L("외부소품\\트랩" + variant + ".rsm") }

    private let device: any MTLDevice
    private let manager: ResourceManager
    private let light: WorldLight
    private var revision: UInt64?
    private var positions: [String: [SIMD3<Float>]] = [:]
    private var assets: [String: RSMModelRenderAsset] = [:]
    private var attempted: Set<String> = []
    private var models: [String: RSMModelRenderResource] = [:]
    var resources: [RSMModelRenderResource] { Array(models.values) }

    init(device: any MTLDevice, manager: ResourceManager, light: WorldLight) {
        self.device = device
        self.manager = manager
        self.light = light
    }

    func synchronize(scene: MapScene) {
        guard revision != scene.groundRevision else { return }
        revision = scene.groundRevision
        var next: [String: [SIMD3<Float>]] = [:]
        for unit in scene.groundUnits.values {
            guard let variant = Self.variants[unit.kind] else { continue }
            let p = scene.mapGrid.worldPosition(for: unit.position)
            next[variant, default: []].append([p.x, -p.z, p.y])
        }
        let previous = positions
        positions = next
        for variant in Set(previous.keys).union(next.keys) where previous[variant] != next[variant] {
            rebuild(variant)
            guard next[variant] != nil, attempted.insert(variant).inserted else { continue }
            let name = Self.name(for: variant)
            Task { [weak self, manager] in
                do {
                    let model = try await manager.model(forName: name)
                    let images = await manager.textureImages(forNames: model.textureNames, removesMagentaPixels: true)
                    guard let self else { return }
                    assets[variant] = RSMModelRenderAsset(name: name, rsm: model.rsm, instance: .identity, textureImages: images)
                    rebuild(variant)
                } catch {
                    logger.warning("Could not load Hunter trap model \(name): \(error)")
                }
            }
        }
    }

    private func rebuild(_ variant: String) {
        guard let points = positions[variant], let asset = assets[variant] else {
            models.removeValue(forKey: variant)
            return
        }
        let instances = points.map { RSMModelInstance(position: $0, rotation: .zero, scale: .init(repeating: 0.2)) }
        models[variant] = RSMModelRenderResource(device: device, prototype: asset, instances: instances, light: light)
    }
}
