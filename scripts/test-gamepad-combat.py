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
methods='\n'.join(method(s) for s in ['func attackMonster(', 'private func cancelArrivalAction(', 'private func stopGamepadAttack(', 'func gamepadPrimary(', 'func gamepadCancel(', 'func gamepadInterruptAttack(', 'func selectTarget(', 'func gamepadResetForMapChange('])
harness='''
import Foundation
import Testing
@testable import RagnarokGame
typealias GameObjectID = UInt32
@MainActor final class MapScene {
 enum Kind { case monster, npc }
 typealias MapSceneMapObject = Object
 enum Damage { case normal, _repeat }
 struct Object { var objectID: UInt32; var gridPosition = SIMD2<Int>.zero; var type = Kind.monster; var isDead = false; var job = 0; func nextPosition(at: ContinuousClock.Instant) -> SIMD2<Int>? { nil } }
 enum Decision { case alreadyInRange, moveTo(SIMD2<Int>), noPath }
 struct State { var isPlayerDead = false; var selectedTargetType: Kind? }
 final class Session {
   weak var mapScene: MapScene?
   struct Status { var attackRange = 1 }
   var playerStatus = Status()
   var actions: [(Damage,UInt32)] = []
   var stops: [SIMD2<Int>] = []
   func requestMove(to position: SIMD2<Int>) { stops.append(position) }
   func requestAction(_ action: Damage, onTarget target: UInt32) { actions.append((action,target)) }
   func talkToNPC(npcID: UInt32) {}
   func pickUpItem(objectID: UInt32) {}
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
 var arrivalTask: Task<Void, any Error>?
 var pendingArrivalAction: (@MainActor () -> Void)?
 var decision = Decision.alreadyInRange
 var moves: [SIMD2<Int>] = []
 init() { playSession.mapScene = self; selectedTarget = objects[2] }
 func requestMove(to position: SIMD2<Int>) { moves.append(position) }
 func decideMovement(from: SIMD2<Int>, toward: SIMD2<Int>, within: Int) -> Decision { decision }
 func nearestItem(fromPosition: SIMD2<Int>) -> Object? { nil }
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
