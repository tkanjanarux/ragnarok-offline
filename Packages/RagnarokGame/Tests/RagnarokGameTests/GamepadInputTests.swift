import Testing
@testable import RagnarokGame

struct GamepadInputTests {
    private func armed() -> GamepadReducer {
        var r = GamepadReducer(); _ = r.sample(.init(), now: 0, available: true, blocked: false); return r
    }
    @Test func deadzoneFiniteAndNormalized() {
        #expect(GamepadReducer.axis(SIMD2(0.1,0.1)) == .zero)
        #expect(GamepadReducer.axis(SIMD2(Float.nan,0)) == .zero)
        let v = GamepadReducer.axis(SIMD2(1,1))
        #expect(abs(v.x * v.x + v.y * v.y - 1) < 0.001)
        #expect(GamepadReducer.axis(SIMD2(0.23,0)).x < 0.02)
    }
    @Test func cameraRelativeDirectionMatchesTouchAxes() {
        let v = GamepadReducer.worldDirection(SIMD2(0,1), azimuth: .pi / 2)
        #expect(abs(v.x - 1) < 0.001 && abs(v.y) < 0.001)
        let back = GamepadReducer.worldDirection(SIMD2(1,0), azimuth: .pi)
        #expect(abs(back.x + 1) < 0.001)
    }
    @Test func movementRateAndNoCatchUpBurst() {
        var r = armed(); let i = GamepadInput(left: SIMD2(1,0))
        #expect(r.sample(i,now: 0,available: true,blocked: false).move != nil)
        for t in [0.02,0.05,0.1,0.199] { #expect(r.sample(i,now: t,available: true,blocked: false).move == nil) }
        #expect(r.sample(i,now: 0.201,available: true,blocked: false).move != nil)
        #expect(r.sample(i,now: 20,available: true,blocked: false).move != nil)
        #expect(r.sample(i,now: 20.01,available: true,blocked: false).move == nil)
    }
    @Test func heldActionDoesNotRepeatAndBlockedPressNeverReplays() {
        var r = armed(); let a = GamepadInput(buttons: [.a])
        #expect(r.sample(a,now: 1,available: true,blocked: false).command == .primary)
        #expect(r.sample(a,now: 2,available: true,blocked: false).command == nil)
        _ = r.sample(.init(),now: 3,available: true,blocked: false)
        #expect(r.sample(a,now: 4,available: true,blocked: true).command == nil)
        #expect(r.sample(a,now: 5,available: true,blocked: false).command == nil)
        _ = r.sample(.init(),now: 6,available: true,blocked: false)
        #expect(r.sample(a,now: 7,available: true,blocked: false).command == .primary)
    }
    @Test func disconnectBackgroundAndMapResetRequireNeutral() {
        var r = armed(); let held = GamepadInput(left: SIMD2(1,0),buttons: [.x])
        _ = r.sample(held,now: 1,available: false,blocked: false)
        #expect(r.sample(held,now: 2,available: true,blocked: false).command == nil)
        #expect(r.sample(held,now: 3,available: true,blocked: false).move == nil)
        _ = r.sample(.init(),now: 4,available: true,blocked: false)
        #expect(r.sample(held,now: 5,available: true,blocked: false).command == .shortcut(row: 0,column: 0))
        r.reset()
        #expect(r.sample(held,now: 6,available: true,blocked: false).move == nil)
    }
    @Test func modalAllowsOnlyCancelAndMenuAndRequiresRelease() {
        var r = armed()
        let result = r.sample(.init(left: SIMD2(1,0),right: SIMD2(1,0),buttons: [.a,.x,.rightShoulder]),now: 1,available: true,blocked: true)
        #expect(result.command == nil && result.move == nil && result.camera == .zero)
        #expect(r.sample(.init(buttons: [.b]),now: 2,available: true,blocked: true).command == .cancel)
        #expect(r.sample(.init(buttons: [.menu]),now: 3,available: true,blocked: true).command == .menu)
        #expect(r.sample(.init(left: SIMD2(1,0)),now: 4,available: true,blocked: false).move == nil)
    }
    @Test func triggerChordsAreDeterministicAndDoNotLeakCancel() {
        for (index,button) in [GamepadInput.Button.a,.b,.x,.y].enumerated() {
            var r = armed()
            #expect(r.sample(.init(buttons:[button],leftTrigger:true),now:1,available:true,blocked:false).command == .shortcut(row:0,column:index))
            r = armed()
            #expect(r.sample(.init(buttons:[button],leftTrigger:true,rightTrigger:true),now:1,available:true,blocked:false).command == .shortcut(row:0,column:index+4))
        }
    }
    @Test func pressingTriggerOnHeldFaceDoesNotFireAgain() {
        var r = armed()
        _ = r.sample(.init(buttons:[.a]),now:1,available:true,blocked:false)
        #expect(r.sample(.init(buttons:[.a],leftTrigger:true),now:2,available:true,blocked:false).command == nil)
    }
    @Test func cameraDeltaIsBoundedAfterLongFrame() {
        var r = armed()
        let f = r.sample(.init(right: SIMD2(1,0)),now:100,available:true,blocked:false)
        #expect(f.camera.x == 0.05)
    }
    @Test func actionRateDropsInsteadOfQueuesAndOneActionPerSample() {
        var r = armed()
        #expect(r.sample(.init(buttons:[.a,.x]),now:1,available:true,blocked:false).command == .primary)
        _ = r.sample(.init(),now:1.01,available:true,blocked:false)
        #expect(r.sample(.init(buttons:[.y]),now:1.02,available:true,blocked:false).command == nil)
        #expect(r.sample(.init(buttons:[.y]),now:2,available:true,blocked:false).command == nil)
    }
    @Test func targetRingDoesNotSwitchWhenMonstersSpawnOrMove() {
        var ring = GamepadTargetRing()
        ring.update([.init(id:2,position:SIMD2(1,0)),.init(id:1,position:SIMD2(-1,0))],origin:.zero,facing:SIMD2(1,0))
        #expect(ring.cycle(1) == 2)
        ring.update([.init(id:2,position:SIMD2(8,0)),.init(id:1,position:SIMD2(1,0)),.init(id:3,position:SIMD2(0.5,0))],origin:.zero,facing:SIMD2(1,0))
        #expect(ring.selected == 2 && ring.order == [2,1,3])
        #expect(ring.cycle(-1) == 3)
    }
    @Test func invalidTargetIsClearedWithoutAutoAcquisitionAndWarpResets() {
        var ring = GamepadTargetRing()
        ring.update([.init(id:1,position:.zero),.init(id:2,position:.zero)],origin:.zero,facing:SIMD2(1,0))
        #expect(ring.cycle(1) == 1)
        ring.update([.init(id:2,position:.zero)],origin:.zero,facing:SIMD2(1,0))
        #expect(ring.selected == nil)
        ring.reset(); #expect(ring.order.isEmpty && ring.selected == nil)
    }
    @Test func firstLockUsesCurrentFacingButNeverAutoLocks() {
        var ring = GamepadTargetRing()
        let candidates = [GamepadTargetRing.Candidate(id: 1,position: SIMD2(-1,0)), .init(id: 2,position: SIMD2(1,0))]
        ring.update(candidates,origin:.zero,facing:SIMD2(-1,0))
        #expect(ring.selected == nil)
        ring.update(candidates,origin:.zero,facing:SIMD2(0.1,0))
        #expect(ring.cycle(1) == 2)
    }

    @Test func touchSelectedTargetIsPreservedOnlyWhileEligible() {
        var ring = GamepadTargetRing()
        ring.update([.init(id: 1,position:.zero),.init(id: 2,position:SIMD2(1,0))],origin:.zero,facing:SIMD2(1,0))
        #expect(ring.select(2) && ring.selected == 2)
        #expect(!ring.select(99) && ring.selected == 2)
        ring.update([.init(id: 1,position:.zero)],origin:.zero,facing:SIMD2(1,0))
        #expect(!ring.select(2) && ring.selected == nil)
    }

    @Test func shortLookaheadCoversSendIntervalWithoutChangingServerSpeed() {
        for speed in [50,60,100,150,200,300,600] {
            let cells = GamepadReducer.lookahead(speedMilliseconds: speed)
            #expect((1...5).contains(cells))
            #expect(cells * speed >= 200)
        }
        #expect(GamepadReducer.lookahead(speedMilliseconds: 0) <= 5)
    }

    @Test func cancelledArrivalCannotResumeEvenForSameMonster() {
        var lease = GamepadAttackLease()
        let old = lease.begin(12)
        #expect(lease.accepts(old, target:12))
        #expect(lease.cancel() == true)
        #expect(lease.cancel() == false) // One network stop, not every tick.
        let current = lease.begin(12)
        #expect(!lease.accepts(old, target:12))
        #expect(lease.accepts(current, target:12))
        #expect(!lease.accepts(current, target:13))
    }
    @Test func allEightChordsAndDpadTeamScope() {
        for (index,button) in [GamepadInput.Button.a,.b,.x,.y].enumerated() {
            var r = armed()
            #expect(r.sample(.init(buttons:[button],rightTrigger:true),now:1,available:true,blocked:false).command == .shortcut(row:0,column:index+4))
        }
        for (button,verb) in [(GamepadInput.Button.up,"follow"),(.right,"assist"),(.down,"stop"),(.left,"hunt")] {
            var r = armed()
            #expect(r.sample(.init(buttons:[button]),now:1,available:true,blocked:false).command == .companion(verb))
        }
    }
    @Test func teamCommandsRequireMatchingAcknowledgementsAndCapabilities() {
        var plan = GamepadTeamPlan()
        #expect(plan.begin("hunt", members:[1], teamMode:true, hunt:false) == false)
        #expect(plan.begin("assist", members:[], teamMode:true, hunt:true) == false)
        #expect(plan.begin("follow", members:[2,1], teamMode:true, hunt:true) == true)
        #expect(plan.steps.map(\.action) == ["teamoff","follow 1","follow 2"])
        #expect(plan.acknowledge(message:"Assist mode.",ready:true,members:[1,2]) == true)
        #expect(plan.acknowledge(message:"Following.",ready:false,members:[1,2]) == false)
        #expect(plan.steps.isEmpty)
        #expect(plan.begin("hunt", members:[1,2], teamMode:true, hunt:true) == true)
        #expect(plan.steps.map(\.action) == ["teamoff","hunt on"])
        #expect(plan.acknowledge(message:"Assist mode.",ready:true,members:[1]) == false)
        #expect(plan.steps.isEmpty)
        #expect(plan.begin("stop", members:[1], teamMode:false, hunt:true) == true)
        #expect(plan.steps.map(\.action) == ["hunt off","stop 1"])
        plan.cancel(); #expect(plan.steps.isEmpty)
    }

    @Test func movingOverridesAttackEvenWhileMovePacketIsRateLimited() {
        var r = armed()
        _ = r.sample(.init(left:SIMD2(1,0)),now:1,available:true,blocked:false)
        let f = r.sample(.init(left:SIMD2(1,0),buttons:[.a]),now:1.01,available:true,blocked:false)
        #expect(f.cancelAttack && f.move == nil && f.command == nil)
    }

}
