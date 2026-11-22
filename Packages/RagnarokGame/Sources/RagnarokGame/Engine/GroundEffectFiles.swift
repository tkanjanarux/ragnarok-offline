import RagnarokCore
import RagnarokFileFormats
import RagnarokRenderAssets
import RagnarokResources

/// Inspect the resource provider currently selected on this device, including the
/// textures named inside each STR and RSM. Packs can differ between installations.
@MainActor
enum GroundEffectFiles {
    static func inspect(_ manager: ResourceManager, report: (String) -> Void) async {
        let effects: [(String, [String])] = [
            ("Fire Pillar", ["magic_red.tga", "firepillar.str", "firepillarbomb.str"]),
            ("Fire Wall", ["firewall1.str"]), ("Safety Wall", ["safetywall.str"]),
            ("Sanctuary", ["magic_green.tga"]), ("Pneuma", ["pneuma1.str"]),
            ("Quagmire", ["quagmire.str"]), ("Storm Gust", ["stormgust.str"]),
            ("Lord of Vermilion", ["lord.str"]), ("Warp Portal", ["ring_blue.tga"]),
        ]
        for (name, files) in effects {
            var unreadable: Set<String> = []
            for file in files {
                let path = ResourcePath.effectDirectory.appending(file)
                do {
                    if file.hasSuffix(".str") {
                        let data = try await manager.contentsOfResource(at: path)
                        let animation = try STR(data: data)
                        for texture in Set(animation.layers.flatMap(\.textures)) {
                            let texturePath = ResourcePath.effectDirectory.appending(subpath: texture)
                            if (try? await manager.image(at: texturePath, removesMagentaPixels: true)) == nil {
                                unreadable.insert(texturePath.description)
                            }
                        }
                    } else {
                        _ = try await manager.image(at: path)
                    }
                } catch { unreadable.insert(path.description) }
            }
            report(result(name, unreadable))
        }
        for variant in GroundTrapModels.variants.values.sorted() {
            let modelName = GroundTrapModels.name(for: variant)
            var unreadable: Set<String> = []
            do {
                let model = try await manager.model(forName: modelName)
                for texture in model.textureNames {
                    let path = ResourcePath.textureDirectory.appending(subpath: texture)
                    if (try? await manager.image(at: path, removesMagentaPixels: true)) == nil {
                        unreadable.insert(L2K(path.description))
                    }
                }
            } catch { unreadable.insert("data/model/" + L2K(modelName)) }
            report(result("Hunter Trap " + variant, unreadable))
        }
    }

    private static func result(_ name: String, _ unreadable: Set<String>) -> String {
        unreadable.isEmpty ? "\(name) · ไฟล์ครบ" : "\(name) · อ่านไม่ได้: " + unreadable.sorted().joined(separator: ", ")
    }
}
