import Foundation
import RagnarokEffects
import RagnarokFileFormats
import RagnarokModels
import RagnarokPackets
import Testing
@testable import RagnarokGame

@MainActor
@Test func groundUnitLifecycle() throws {
    let bytes = Data([71,82,65,84,1,2,8,0,0,0,8,0,0,0] + Array(repeating: 0, count: 8*8*20))
    let grid = MapGrid(gat: try GAT(data: bytes))
    let audio = GameAudioPlayer(resourceManager: .testing)
    let account = AccountInfo(from: PACKET_AC_ACCEPT_LOGIN())
    let character = CharacterInfo()
    let session = PlaySession(context: .testing, audioPlayer: audio, account: account, character: character)
    let scene = MapScene(mapName: "dew_dun02.rsw", mapGrid: grid, account: account, character: character,
                         playerPosition: [0,0], resourceManager: .testing, audioPlayer: audio, playSession: session)
    var entry = packet_skill_entry()
    entry.AID = 53
    entry.job = 135
    entry.isVisible = 1
    entry.RadiusRange = 1
    entry.xPos = 3
    entry.yPos = 3
    scene.updateGroundUnit(entry)
    scene.updateGroundUnit(entry)
    #expect(scene.visibleGroundTiles().count == 9)
    #expect(scene.effects.count == 1)
    entry.job = 136
    scene.updateGroundUnit(entry)
    #expect(scene.effects.count == 1)
    scene.removeGroundUnit(entry.AID)
    #expect(scene.visibleGroundTiles().isEmpty && scene.effects.isEmpty)
    for kind: Int32 in [126,127,128,129,131,133,138,140,141,142,143,144,145,147,148,149,150,151,152,153] {
        entry.job = kind
        scene.updateGroundUnit(entry)
        #expect(scene.visibleGroundTiles().count == 1)
    }
    entry.job = 134
    scene.updateGroundUnit(entry)
    #expect(scene.visibleGroundTiles().isEmpty)
    entry.job = 147
    entry.isVisible = 0
    scene.updateGroundUnit(entry)
    #expect(scene.visibleGroundTiles().isEmpty)
    entry.isVisible = 1
    scene.updateGroundUnit(entry)
    scene.jump(toPosition: [1,1])
    #expect(scene.visibleGroundTiles().isEmpty)
    scene.onGroundSkillCast(skillID: .wz_stormgust, sourceObjectID: 123, position: [4,4])
    scene.onGroundSkillCast(skillID: .wz_vermilion, sourceObjectID: 123, position: [4,4])
    #expect(scene.effects.count == 2)
    var hit = PACKET_ZC_NOTIFY_SKILL()
    hit.SKID = 80
    hit.targetID = account.accountID
    hit.count = 7
    hit.damage = 1001
    scene.onMapObjectSkillPerformed(objectSkill: MapObjectSkill(from: hit))
    #expect(scene.combatTexts.count == 7)
    #expect(scene.effects.count >= 9)
    scene.showSkillDamage("Fire Pillar −1001", target: account.accountID)
    #expect(scene.skillDamage[account.accountID]?.text.makeImage() != nil)
}
