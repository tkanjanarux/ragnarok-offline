//
//  SpriteAssetStore.swift
//  RagnarokGame
//
//  Created by Leon Li on 2026/3/25.
//

import Metal
import QuartzCore
import RagnarokRenderAssets
import RagnarokSprite

@MainActor
final class SpriteAssetStore {
    private struct Textures {
        let sprite: AnyObject
        let partTextures: SpritePartTextures
    }

    private let device: any MTLDevice
    private let shadowmap: GroundShadowmap

    private var objectTextures: [GameObjectID : Textures] = [:]
    private lazy var falconTextures = SpritePartTextures(device: device)
    private var itemTextures: [GameObjectID : Textures] = [:]

    init(device: any MTLDevice, shadowmap: GroundShadowmap) {
        self.device = device
        self.shadowmap = shadowmap
    }

    func sync(
        objects: [GameObjectID : MapSceneMapObject],
        items: [GameObjectID : MapSceneDroppedItem],
        worldPositions: [GameObjectID : SIMD3<Float>]
    ) -> [SpriteDrawable] {
        for objectID in Set(objectTextures.keys).subtracting(objects.keys) {
            objectTextures.removeValue(forKey: objectID)
        }

        for objectID in Set(itemTextures.keys).subtracting(items.keys) {
            itemTextures.removeValue(forKey: objectID)
        }

        var sprites: [SpriteDrawable] = []
        sprites.reserveCapacity(objects.count + items.count)

        let frameResolver = SpriteFrameResolver()

        for (objectID, object) in objects {
            guard let composedSprite = object.composedSprite,
                  let worldPosition = worldPositions[objectID] else {
                continue
            }

            let drawable = frameResolver.resolve(
                object,
                composedSprite: composedSprite,
                partTextures: partTextures(for: composedSprite, in: &objectTextures, objectID: objectID),
                worldPosition: worldPosition,
                shadow: shadowmap.shadowFactor(x: worldPosition.x, y: worldPosition.y)
            )
            guard let drawable else {
                continue
            }
            sprites.append(drawable)
            if let falcon = object.falconSprite, object.hasVisibleFalcon,
               let direction = object.resolvedAction?.direction {
                let now = CACurrentMediaTime()
                let flight = object.blitzFlight
                let progress = flight?.targetWeight(at: now) ?? 0
                let position = worldPosition + ((flight?.target ?? worldPosition) - worldPosition) * progress
                let moving = progress > 0 || object.movement?.isMoving == true
                let index = direction.rawValue + (moving && falcon.act.actions.count >= 16 ? 8 : 0)
                let offset = SIMD2<Int32>(Int32(21 * (1 - progress)), Int32(-39 + 22 * progress))
                if let bird = frameResolver.resolve(
                    objectID: objectID, sprite: falcon, partTextures: falconTextures,
                    worldPosition: position, shadow: drawable.shadow, actionIndex: index,
                    elapsed: now, pixelOffset: offset
                ) {
                    sprites.append(bird)
                }
                if let flight, now >= flight.start + FalconFlight.duration { object.blitzFlight = nil }
            }
        }

        for (objectID, item) in items {
            guard let sprite = item.sprite,
                  let worldPosition = worldPositions[objectID] else {
                continue
            }

            let drawable = frameResolver.resolve(
                objectID: objectID,
                sprite: sprite,
                partTextures: partTextures(for: sprite, in: &itemTextures, objectID: objectID),
                worldPosition: worldPosition,
                shadow: shadowmap.shadowFactor(x: worldPosition.x, y: worldPosition.y)
            )
            guard let drawable else {
                continue
            }
            sprites.append(drawable)
        }

        sprites.sort {
            if $0.worldPosition.y == $1.worldPosition.y {
                $0.objectID < $1.objectID
            } else {
                $0.worldPosition.y > $1.worldPosition.y
            }
        }

        return sprites
    }

    private func partTextures(
        for sprite: AnyObject,
        in textures: inout [GameObjectID : Textures],
        objectID: GameObjectID
    ) -> SpritePartTextures {
        if let existing = textures[objectID], existing.sprite === sprite {
            return existing.partTextures
        }

        let partTextures = SpritePartTextures(device: device)
        textures[objectID] = Textures(sprite: sprite, partTextures: partTextures)
        return partTextures
    }
}
