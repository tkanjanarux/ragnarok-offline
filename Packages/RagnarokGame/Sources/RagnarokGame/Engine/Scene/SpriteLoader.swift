//
//  SpriteLoader.swift
//  RagnarokGame
//
//  Created by Leon Li on 2026/9/4.
//

import RagnarokResources
import RagnarokSprite

@MainActor
final class SpriteLoader {
    private struct ObjectLoadTask {
        let configuration: ComposedSprite.Configuration
        let task: Task<Void, Never>
    }

    private var falconLoad: Task<Void, Never>?
    private var falconSprite: SpriteResource?
    private let resourceManager: ResourceManager

    private var objectLoadTasks: [GameObjectID : ObjectLoadTask] = [:]
    private var itemLoadTasks: [GameObjectID : Task<Void, Never>] = [:]

    init(resourceManager: ResourceManager) {
        self.resourceManager = resourceManager
    }

    func load(
        objects: [GameObjectID : MapSceneMapObject],
        items: [GameObjectID : MapSceneDroppedItem]
    ) {
        for objectID in Set(objectLoadTasks.keys).subtracting(objects.keys) {
            objectLoadTasks.removeValue(forKey: objectID)?.task.cancel()
        }

        for objectID in Set(itemLoadTasks.keys).subtracting(items.keys) {
            itemLoadTasks.removeValue(forKey: objectID)?.cancel()
        }

        if falconLoad == nil && objects.values.contains(where: { $0.hasVisibleFalcon }) {
            falconLoad = Task { [weak self, resourceManager] in
                let path = ResourcePath.spriteDirectory.appending(path: K2L(["이팩트", "매"]))
                let sprite = try? await resourceManager.sprite(at: path)
                if !Task.isCancelled { self?.falconSprite = sprite }
            }
        }
        for object in objects.values {
            object.falconSprite = object.hasVisibleFalcon ? falconSprite : nil
            loadSprite(forObject: object)
        }

        for item in items.values {
            loadSprite(forItem: item)
        }
    }

    func cancelAll() {
        falconLoad?.cancel()
        falconLoad = nil
        for loadTask in objectLoadTasks.values {
            loadTask.task.cancel()
        }
        objectLoadTasks.removeAll()

        for loadTask in itemLoadTasks.values {
            loadTask.cancel()
        }
        itemLoadTasks.removeAll()
    }

    private func loadSprite(forObject object: MapSceneMapObject) {
        let objectID = object.objectID
        let configuration = ComposedSprite.Configuration(object: object)

        if object.composedSprite?.configuration != configuration {
            object.composedSprite = nil
        }
        if let loadTask = objectLoadTasks[objectID], loadTask.configuration != configuration {
            objectLoadTasks.removeValue(forKey: objectID)?.task.cancel()
        }

        if object.job == 45 { // JT_WARPNPC
            return
        }

        guard object.composedSprite == nil, objectLoadTasks[objectID] == nil else {
            return
        }

        let task = Task { [weak self, weak object] in
            guard let self else {
                return
            }
            defer {
                // A newer appearance may have replaced this load already.
                if objectLoadTasks[objectID]?.configuration == configuration {
                    objectLoadTasks.removeValue(forKey: objectID)
                }
            }

            guard let composedSprite = try? await ComposedSprite(
                configuration: configuration,
                resourceManager: resourceManager
            ) else {
                return
            }

            // The object left the map or changed how it looks while this was loading.
            guard let object, ComposedSprite.Configuration(object: object) == configuration else {
                return
            }

            object.composedSprite = composedSprite
        }

        objectLoadTasks[objectID] = ObjectLoadTask(configuration: configuration, task: task)
    }

    private func loadSprite(forItem item: MapSceneDroppedItem) {
        let objectID = item.objectID
        let itemID = item.itemID

        guard item.sprite == nil, itemLoadTasks[objectID] == nil else {
            return
        }

        itemLoadTasks[objectID] = Task { [weak self, weak item] in
            guard let self else {
                return
            }
            defer {
                itemLoadTasks.removeValue(forKey: objectID)
            }

            guard let sprite = try? await resourceManager.itemSprite(forItemID: itemID) else {
                return
            }

            item?.sprite = sprite
        }
    }
}
