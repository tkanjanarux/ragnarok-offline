"""Compile actual MapScene combat methods against an injected movement/packet seam.
Not a live server, Apple renderer, or hardware test. No reimplementation of combat.
"""
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]; out=Path(sys.argv[1])
source=(root/'Packages/RagnarokGame/Sources/RagnarokGame/Engine/Scene/MapScene.swift').read_text()
def method(signature):
    start=source.index(signature); brace=source.index('{',start); depth=1; i=brace+1
    while depth:
        depth += (source[i]=='{') - (source[i]=='}'); i+=1
    return source[start:i].replace('private func','func')
methods='\n'.join(method(s) for s in ['func attackMonster(', 'private func cancelArrivalAction(', 'private func stopGamepadAttack(', 'func gamepadPrimary(', 'func gamepadCancel(', 'func gamepadInterruptAttack(', 'func selectTarget(', 'func gamepadResetForMapChange(', 'func gamepadCanAcquire(', 'func useGamepadSkill('])
sceneSource = source
source=(root/'Packages/RagnarokGame/Sources/RagnarokGame/Engine/PlaySession.swift').read_text()
shortcutMethod=method('func useShortcut(')
source=sceneSource
harness='''
import Foundation
import Testing
@testable import RagnarokGame
typealias GameObjectID = UInt32
@MainActor final class MapScene {
 enum Kind { case monster, npc, pc }
 struct Effects: OptionSet { let rawValue: Int; static let cloak = Self(rawValue:1); static let hide = Self(rawValue:2); static let invisible = Self(rawValue:4) }
 typealias MapSceneMapObject = Object
 enum Damage { case normal, _repeat }
 struct Object { var objectID: UInt32; var gridPosition = SIMD2<Int>.zero; var type = Kind.monster; var isDead = false; var job = 0; var cast: Int?; var effectState: Effects = []; func nextPosition(at: ContinuousClock.Instant) -> SIMD2<Int>? { nil } }
 enum Decision { case alreadyInRange, moveTo(SIMD2<Int>), noPath }
 struct State { var isPlayerDead = false; var selectedTargetType: Kind? }
 @MainActor final class Session {
   weak var mapScene: MapScene?
   struct Status { var attackRange = 1 }
   var playerStatus = Status()
   var actions: [(Damage,UInt32)] = []
   var stops: [SIMD2<Int>] = []
   func requestMove(to position: SIMD2<Int>) { stops.append(position) }
   func requestAction(_ action: Damage, onTarget target: UInt32) { actions.append((action,target)) }
   enum Shortcut { case empty, item(Int), skill(Int,Int) }
   struct Item { var itemID: Int; var index: Int }
   struct Inventory { var items: [Int:Item] = [7:Item(itemID:77,index:7)] }
   struct Skills { var skills: [Int:SkillInfo] = [1:SkillInfo(flag:1), 2:SkillInfo(flag:16)] }
   var inventory = Inventory(); var skillList = Skills(); var usedItems: [Int] = []
   func useItem(at index:Int) { usedItems.append(index) }
'''+shortcutMethod+'''
   var casts: [UInt32] = []
   func useSkill(skillID:Int, level:Int, onTarget:UInt32) { casts.append(onTarget) }
   func talkToNPC(npcID: UInt32) {}
   var pickups: [UInt32] = []
   func pickUpItem(objectID: UInt32) { pickups.append(objectID) }
 }
 var playSession = Session()
 var state = State()
 var player = Object(objectID: 1)
 var objects: [UInt32:Object] = [2:Object(objectID:2)]
 var selectedTargetID: UInt32?
 var targetSelector: Int?
 var selectedTarget: Object? {
   get { selectedTargetID.flatMap { objects[$0] } }
   set { selectedTargetID = newValue?.objectID }
 }
 var gamepadAttack = GamepadAttackLease()
 var gamepadAttackValidation: GamepadTargetValidation?
 final class Path {
   var straight = true; var path = [SIMD2<Int>.zero]
   func canMoveStraight(from:SIMD2<Int>,to:SIMD2<Int>) -> Bool { straight }
   func findPath(from:SIMD2<Int>,to:SIMD2<Int>,within:Int) -> [SIMD2<Int>] { path }
 }
 var pathFinder = Path()
 var arrivalTask: Task<Void, any Error>?
 var pendingArrivalAction: (@MainActor () -> Void)?
 var decision = Decision.alreadyInRange
 var moves: [SIMD2<Int>] = []
 init() { playSession.mapScene = self; selectedTarget = objects[2]; objects[1] = player }
 func requestMove(to position: SIMD2<Int>) { moves.append(position) }
 func decideMovement(from: SIMD2<Int>, toward: SIMD2<Int>, within: Int) -> Decision { decision }
 func useSkill(_ skill:SkillInfo,level:Int) {}
 var item: Object?
 func nearestItem(fromPosition: SIMD2<Int>) -> Object? { item }
'''+methods+'''
}
@MainActor struct GamepadCombatTests {
 @Test func singlePressApproachesThenRepeatsUsingActualSceneMethods() {
   let scene = MapScene(); scene.decision = .moveTo(SIMD2(5,6))
   #expect(scene.gamepadPrimary() == nil)
   #expect(scene.moves == [SIMD2(5,6)] && scene.playSession.actions.isEmpty)
   scene.decision = .alreadyInRange; scene.pendingArrivalAction?()
   #expect(scene.playSession.actions.count == 1)
   #expect(scene.playSession.actions[0].0 == ._repeat && scene.playSession.actions[0].1 == 2)
 }
 @Test func movementAndCancelSendOneServerStopAndInvalidateCapturedArrival() {
   for cancel in [false,true] {
     let scene = MapScene(); scene.decision = .moveTo(SIMD2(5,6))
     _ = scene.gamepadPrimary(); let stale = scene.pendingArrivalAction
     if cancel { scene.gamepadCancel() } else { scene.gamepadInterruptAttack() }
     scene.decision = .alreadyInRange; stale?()
     scene.gamepadInterruptAttack()
     #expect(scene.pendingArrivalAction == nil && scene.playSession.actions.count == 1)
     #expect(scene.playSession.stops == [.zero])
     #expect(scene.playSession.actions[0].0 == .normal && scene.playSession.actions[0].1 == 0)
   }
 }
 @Test func contextualLootSupersedesSoftAttackArrival() {
   let scene = MapScene(); scene.selectTarget(nil); scene.decision = .moveTo(SIMD2(5,6))
   _ = scene.gamepadPrimary(targetID:2,validate:{ _ in true })
   let stale = scene.pendingArrivalAction
   scene.item = .init(objectID:7)
   _ = scene.gamepadPrimary()
   scene.decision = .alreadyInRange; stale?()
   #expect(scene.playSession.pickups == [7] && scene.gamepadAttack.target == nil)
   #expect(!scene.playSession.actions.contains { $0.0 == ._repeat })
 }
 @Test func actualShortcutPipelineDispatchesOneTargetedSkillAndItemsIgnorePreview() {
   let scene = MapScene(); scene.selectTarget(nil)
   scene.playSession.useShortcut(.skill(1,1),gamepadTarget:2,gamepadValidation:{ _ in true })
   #expect(scene.playSession.casts == [2] && scene.pendingArrivalAction == nil && scene.selectedTargetID == nil)
   scene.playSession.useShortcut(.item(77),gamepadTarget:999,gamepadValidation:{ _ in false })
   #expect(scene.playSession.usedItems == [7] && scene.playSession.casts == [2])
 }
 @Test func previewUpdatesDoNotSwitchOrChainCurrentRepeat() {
   let scene = MapScene(); scene.selectTarget(nil)
   _ = scene.gamepadPrimary(targetID:2,validate:{ _ in true })
   var preview = GamepadDirectionalTargets()
   for id:UInt32 in [3,4,5] { preview.update([.init(id:id,position:SIMD2(1,0))],origin:.zero,facing:SIMD2(1,0)) }
   #expect(preview.preview == 5 && scene.gamepadAttack.target == 2)
   #expect(scene.playSession.actions.count == 1 && scene.selectedTargetID == nil)
   scene.gamepadInterruptAttack()
   preview.update([.init(id:6,position:SIMD2(1,0))],origin:.zero,facing:SIMD2(1,0))
   #expect(scene.gamepadAttack.target == nil && scene.playSession.actions.filter { $0.0 == ._repeat }.count == 1)
 }
 @Test func softActionNeverLocksOrChainsAndRevalidatesArrival() {
   let scene = MapScene(); scene.selectTarget(nil); scene.decision = .moveTo(SIMD2(5,6))
   var visible = true
   _ = scene.gamepadPrimary(targetID:2,validate:{ _ in visible })
   #expect(scene.selectedTargetID == nil && scene.gamepadAttack.target == 2)
   let stale = scene.pendingArrivalAction; visible = false
   scene.decision = .alreadyInRange; stale?()
   #expect(!scene.playSession.actions.contains { $0.0 == ._repeat })
   #expect(scene.gamepadAttack.target == nil)
   #expect(scene.selectedTargetID == nil)
 }
 @Test func acquireRejectsHiddenDeadWallsFarAndUnreachable() {
   let scene = MapScene()
   #expect(scene.gamepadCanAcquire(2))
   scene.objects[2]?.effectState = .hide; #expect(!scene.gamepadCanAcquire(2))
   scene.objects[2]?.effectState = []; scene.objects[2]?.isDead = true; #expect(!scene.gamepadCanAcquire(2))
   scene.objects[2]?.isDead = false; scene.pathFinder.straight = false; #expect(!scene.gamepadCanAcquire(2))
   scene.pathFinder.straight = true; scene.pathFinder.path = []; #expect(!scene.gamepadCanAcquire(2))
   scene.pathFinder.path = [.zero]; scene.objects[2]?.gridPosition = SIMD2(13,0); #expect(!scene.gamepadCanAcquire(2))
 }
 @Test func directedSkillSendsOnceAndNeverInstallsAnArrivalCast() {
   let scene = MapScene(); scene.selectedTarget = nil
   scene.useGamepadSkill(SkillInfo(flag:1),level:1,targetID:2,validate:{ _ in true })
   #expect(scene.playSession.casts == [2] && scene.pendingArrivalAction == nil && scene.selectedTargetID == nil)
   scene.useGamepadSkill(SkillInfo(flag:1),level:1,targetID:2,validate:{ _ in false })
   scene.objects[2]?.gridPosition = SIMD2(6,0)
   scene.useGamepadSkill(SkillInfo(flag:1),level:1,targetID:2,validate:{ _ in true })
   #expect(scene.playSession.casts == [2] && scene.pendingArrivalAction == nil)
   scene.gamepadResetForMapChange(); #expect(scene.pendingArrivalAction == nil)
 }
 @Test func supportAndGroundCannotBeHijackedByMonsterCandidate() {
   let scene = MapScene()
   for flag in [0,2,16,32,4] { scene.useGamepadSkill(SkillInfo(flag:flag),level:1,targetID:2,validate:{ _ in true }) }
   #expect(scene.playSession.casts.isEmpty)
   scene.useGamepadSkill(SkillInfo(flag:16),level:1,targetID:1,validate:nil)
   #expect(scene.playSession.casts == [1])
   scene.objects[1]?.effectState = .cloak
   scene.useGamepadSkill(SkillInfo(flag:4),level:1,targetID:1,validate:nil)
   #expect(scene.playSession.casts == [1,1]) // Self toggles/buffs must work while hidden.
 }
 @Test func sameSceneWarpCancelsArrivalWithoutSendingOldCoordinates() {
   let scene = MapScene(); scene.decision = .moveTo(SIMD2(5,6))
   _ = scene.gamepadPrimary(); let stale = scene.pendingArrivalAction
   scene.gamepadResetForMapChange(); scene.player.gridPosition = SIMD2(50,60)
   scene.decision = .alreadyInRange; stale?()
   #expect(scene.playSession.actions.isEmpty && scene.playSession.stops.isEmpty)
   #expect(scene.pendingArrivalAction == nil && scene.selectedTarget == nil)
 }
 @Test func touchAttackCanBeCancelledOrRetargetedByController() {
   for retarget in [false,true] {
     let scene = MapScene(); scene.attackMonster(targetID:2)
     #expect(scene.playSession.actions.first?.0 == ._repeat)
     if retarget { scene.selectTarget(nil) } else { scene.gamepadCancel() }
     #expect(scene.playSession.actions.count == 2 && scene.playSession.actions.last?.1 == 0)
     #expect(scene.pendingArrivalAction == nil)
   }
 }
 @Test func oldSceneNeverSendsStopToNewMapAndDeadTargetDoesNotAttack() {
   let scene = MapScene(); _ = scene.gamepadPrimary()
   scene.playSession.mapScene = nil; scene.gamepadCancel()
   #expect(scene.playSession.actions.count == 1)
   let dead = MapScene(); dead.objects[2]?.isDead = true
   dead.attackMonster(targetID:2); #expect(dead.playSession.actions.isEmpty)
 }
 @Test func replacementAttackRejectsOldArrivalEvenWithSameID() {
   let scene = MapScene(); scene.decision = .moveTo(SIMD2(5,6))
   _ = scene.gamepadPrimary(); let stale = scene.pendingArrivalAction
   scene.gamepadCancel(); scene.selectedTarget = scene.objects[2]
   _ = scene.gamepadPrimary(); scene.decision = .alreadyInRange
   let count = scene.playSession.actions.count; stale?()
   #expect(scene.playSession.actions.count == count)
   scene.pendingArrivalAction?(); #expect(scene.playSession.actions.last?.0 == ._repeat)
 }
}
'''
(out/'Tests/RagnarokGameTests/GamepadCombatTests.swift').write_text(harness)
