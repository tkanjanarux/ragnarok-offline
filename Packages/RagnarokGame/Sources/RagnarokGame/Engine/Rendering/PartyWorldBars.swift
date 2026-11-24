import RagnarokModels
import simd

enum PartyWorldBars {
    static func make(
        party: PartyState,
        ownID: UInt32,
        mapName: String,
        objects: [GameObjectID: MapSceneMapObject],
        worldPositions: [GameObjectID: SIMD3<Float>],
        visibleIDs: Set<GameObjectID>
    ) -> [MapSceneRenderSnapshot.Bar] {
        party.members.compactMap { member in
            guard member.id != ownID, !member.offline, !member.dead,
                  member.isOnMap(mapName), visibleIDs.contains(member.id),
                  let hp = member.hp, let maximum = member.maxHP, hp > 0, maximum > 0,
                  let object = objects[member.id], object.type == .pc, !object.isDead,
                  !object.effectState.contains(.cloak),
                  !object.effectState.contains(.hide),
                  !object.effectState.contains(.invisible),
                  let position = worldPositions[member.id] else { return nil }
            return MapSceneRenderSnapshot.Bar(
                vertices: BarMesh.partyHealth(hp: Int(hp), maxHp: Int(maximum)).vertices,
                worldPosition: position,
                screenSpace: true
            )
        }
    }
}
