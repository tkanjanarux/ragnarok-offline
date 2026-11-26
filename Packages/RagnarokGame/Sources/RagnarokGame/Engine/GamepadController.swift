#if os(iOS)
import GameController
import Observation
import UIKit
import RagnarokModels

@MainActor @Observable
final class GamepadController: NSObject {
    var connectedName: String?
    var targetName = "No target"
    var companionName = "No active companion"
    var message = ""
    var helpVisible = false
    var labels: [String: String] = [:]
    private var runID = UUID()
    private weak var activeScene: MapScene?
    private weak var presentationRoot: UIViewController?
    private var reducer = GamepadReducer()
    private var ring = GamepadTargetRing()
    private var controller: GCController?
    private var touchRevision: UInt64 = 0
    private var facing = SIMD2<Float>(0, 1)
    private var companionID: UInt32?
    private var companionRequest: UInt32?

    override init() {
        super.init()
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
                     NSNotification.Name.GCControllerDidDisconnect, UITextField.textDidBeginEditingNotification,
                     UITextView.textDidBeginEditingNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(resetInput), name: name, object: nil)
        }
    }
    @objc private func resetInput() {
        reducer.reset(); ring.reset(); activeScene?.gamepadCancel(); targetName = "No target"
    }

    /// Poll live values on the main actor. There are no buffered callback actions to replay.
    /// Enumeration also discovers pads connected before this view starts and hot-plug changes.
    func run(session: PlaySession, runtime: MapSceneRuntime, blocked: () -> Bool,
             menu: () -> Void, cancelWindow: () -> Bool) async {
        let id = UUID(); runID = id
        presentationRoot = Self.topPresentation
        activeScene = runtime.scene
        resetInput()
        companionRequest = nil
        defer {
            runtime.scene.gamepadCancel()
            if runID == id { activeScene = nil; reducer.reset(); ring.reset(); controller = nil; connectedName = nil }
        }
        while !Task.isCancelled && runID == id {
            tick(session: session, runtime: runtime, blocked: blocked(), menu: menu, cancelWindow: cancelWindow)
            do { try await Task.sleep(for: .milliseconds(33)) } catch { break }
        }
    }
    private func tick(session: PlaySession, runtime: MapSceneRuntime, blocked: Bool,
                      menu: () -> Void, cancelWindow: () -> Bool) {
        let scene = runtime.scene
        let devices = GCController.controllers().filter { $0.extendedGamepad != nil }
        let current = controller.flatMap { old in devices.first { $0 === old } } ?? devices.first
        if current !== controller {
            scene.gamepadCancel(); reducer.reset(); ring.reset(); controller = current
            connectedName = current?.vendorName ?? (current == nil ? nil : "Controller")
            if let pad = current?.extendedGamepad {
                labels = ["a": pad.buttonA.localizedName ?? "Bottom", "b": pad.buttonB.localizedName ?? "Right",
                          "x": pad.buttonX.localizedName ?? "Left", "y": pad.buttonY.localizedName ?? "Top",
                          "lb": pad.leftShoulder.localizedName ?? "Left shoulder", "rb": pad.rightShoulder.localizedName ?? "Right shoulder",
                          "lt": pad.leftTrigger.localizedName ?? "Left trigger", "rt": pad.rightTrigger.localizedName ?? "Right trigger"]
            }
        }
        guard let pad = controller?.extendedGamepad else { targetName = "No target"; return }
        var input = GamepadInput(left: SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value),
                                 right: SIMD2(pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value))
        let buttons: [(GamepadInput.Button, GCControllerButtonInput)] = [(.a,pad.buttonA),(.b,pad.buttonB),(.x,pad.buttonX),(.y,pad.buttonY),(.leftShoulder,pad.leftShoulder),(.rightShoulder,pad.rightShoulder),(.menu,pad.buttonMenu),(.up,pad.dpad.up),(.down,pad.dpad.down),(.left,pad.dpad.left),(.right,pad.dpad.right)]
        input.buttons = Set(buttons.filter { $0.1.isPressed }.map(\.0))
        input.leftTrigger = pad.leftTrigger.value > 0.5; input.rightTrigger = pad.rightTrigger.value > 0.5
        let available = UIApplication.shared.applicationState == .active && session.mapScene === scene && !scene.state.isPlayerDead
        if touchRevision != scene.gamepadTouchRevision {
            touchRevision = scene.gamepadTouchRevision; reducer.reset(); ring.reset()
        }
        let uiBlocked = blocked || helpVisible || session.gamepadModalOpen || editingOrPresented
        let frame = reducer.sample(input, now: ProcessInfo.processInfo.systemUptime, available: available,
                                   blocked: uiBlocked || scene.thumbstickValue != .zero || !scene.gamepadTouchGestures.isEmpty)
        if !available { scene.gamepadCancel(); ring.reset(); targetName = "No target"; return }
        if uiBlocked { scene.gamepadCancel(); ring.reset() }
        let origin = SIMD2<Float>(Float(scene.player.gridPosition.x),Float(scene.player.gridPosition.y))
        let left = GamepadReducer.axis(input.left)
        if left != .zero { facing = GamepadReducer.worldDirection(left, azimuth: scene.camera.azimuth) }
        else {
            let angle = -Float(scene.player.action.direction.rawValue) * .pi / 4 - .pi / 2
            facing = SIMD2(cos(angle), sin(angle))
        }
        let candidates = scene.objects.values.filter {
            let d = $0.gridPosition &- scene.player.gridPosition
            return $0.type == .monster && max(abs(d.x),abs(d.y)) <= 12 && runtime.gamepadCanSee($0)
        }.map { GamepadTargetRing.Candidate(id: $0.objectID, position: SIMD2(Float($0.gridPosition.x),Float($0.gridPosition.y))) }
        if let target = scene.selectedTarget, !runtime.gamepadCanSee(target) { scene.gamepadCancel() }
        let old = ring.selected
        ring.update(candidates, origin: origin, facing: facing)
        if old != nil && ring.selected == nil { scene.gamepadCancel() }
        if let id = ring.selected {
            if scene.selectedTargetID != id { scene.selectTarget(scene.objects[id]) }
            if scene.targetSelector?.objectID != id { scene.targetSelector = TargetSelector(objectID: id, showTime: .now) }
            targetName = scene.objects[id]?.name ?? "No target"
        }
        else { targetName = scene.selectedTarget?.name ?? "No target" }
        if let move = frame.move {
            facing = GamepadReducer.worldDirection(move, azimuth: scene.camera.azimuth)
            scene.gamepadMove(facing)
        }
        scene.camera.azimuth = (scene.camera.azimuth + frame.camera.x * 1.8).truncatingRemainder(dividingBy: .pi * 2)
        scene.camera.elevation = min(.pi / 3, max(.pi / 12, scene.camera.elevation + frame.camera.y))
        if let request = companionRequest,
           session.companions.completedSequence == request || !session.companions.pending {
            message = session.companions.message
            companionRequest = nil
        }
        let profiles = session.companions.profiles.filter { $0.active && $0.hp > 0 }.sorted { $0.id < $1.id }
        if !profiles.contains(where: { $0.id == companionID }) { companionID = profiles.first?.id }
        companionName = profiles.first(where: { $0.id == companionID })?.name ?? "No active companion"
        guard let command = frame.command else { return }
        switch command {
        case .menu: if !editingOrPresented { menu() }
        case .cancel:
            if helpVisible { helpVisible = false }
            else if !cancelWindow() {
                if uiBlocked { message = "Use touch to close this window." }
                scene.gamepadCancel(); ring.reset()
            }
        case .target(let direction):
            if let id = ring.cycle(direction) { scene.selectTarget(scene.objects[id]) }
        case .primary:
            if ring.selected == nil {
                if let target = scene.selectedTarget {
                    if target.type == .monster && !ring.select(target.objectID) {
                        message = "Move closer to the selected target."; return
                    }
                } else if let id = ring.cycle(1) { scene.selectTarget(scene.objects[id]) }
            }
            message = scene.gamepadPrimary() ?? ""
        case .shortcut(let row, let column): useShortcut(row: row, column: column, session: session, scene: scene)
        case .nextCompanion:
            if !session.companions.ready { session.companionCommand("list") }
            else if let index = profiles.firstIndex(where: { $0.id == companionID }), !profiles.isEmpty { companionID = profiles[(index + 1) % profiles.count].id }
        case .companion(let verb):
            guard let companionID, session.companions.ready, session.companions.available,
                  !session.companions.pending, !session.companions.transferPending else { message = "Load companions first; D-pad left refreshes the roster."; return }
            session.companionCommand("\(verb) \(companionID)")
            if session.companions.pending {
                companionRequest = session.companions.sequence
                message = "Waiting for companion confirmation…"
            }
        }
    }
    private func useShortcut(row: Int, column: Int, session: PlaySession, scene: MapScene) {
        let rows = session.shortcutList.rows
        guard rows.indices.contains(row), rows[row].indices.contains(column), !session.hasPendingInventoryOperation else { return }
        let shortcut = rows[row][column]
        guard session.isShortcutAvailable(shortcut) else { return }
        if case let .skill(id, level) = shortcut {
            guard scene.player.cast == nil else { return }
            guard let skill = session.skillList.skills[id], skill.level > 0, level > 0, !skill.isPassiveSkill else { message = "This shortcut is not a learned active skill."; return }
            guard !skill.isGroundTargetedSkill else { message = "Ground skills use touch controls in round 1."; return }
            if let cooldown = session.skillCooldown(for: shortcut), cooldown.endTime > .now { return }
            // Prevent the legacy nearest-monster fallback or a delayed approach/cast queue.
            if !skill.isSelfOnlySkill {
                guard let target = scene.selectedTarget else {
                    if skill.isSupportSkill { session.useShortcut(shortcut) }
                    else { message = "Select a target first." }
                    return
                }
                let d = target.gridPosition &- scene.player.gridPosition
                guard max(abs(d.x),abs(d.y)) <= max(1,skill.attackRange) else { message = "Move closer to use this skill."; return }
                guard skill.isSupportSkill || target.type == .monster else { return }
            }
        }
        session.useShortcut(shortcut)
    }
    private static var topPresentation: UIViewController? {
        var top = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
    private var editingOrPresented: Bool {
        func editing(_ view: UIView) -> Bool {
            if view.isFirstResponder && view is any UITextInput { return true }
            return view.subviews.contains(where: editing)
        }
        // GameClient itself presents GameView full-screen. Only a presentation ABOVE
        // that host is modal; treating every root presentation as a modal disables play.
        if Self.topPresentation !== presentationRoot { return true }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .filter(\.isKeyWindow).contains(where: editing)
    }
}

extension PlaySession {
    var gamepadModalOpen: Bool {
        dialog != nil || warpList != nil || npcShop != nil || dealSelectionNPCID != nil || storage != nil
        || itemSelection.visible || cart.visible || refine.visible || equipmentSwitch.visible || equipmentSwitch.compareIndex != nil
        || buyingStore.visible || vending.visible || enchant.visible || rodex.visible || guild.visible || followers.visible
        || pets.visible || rewards.visible || rewards.attendanceVisible || chatRoom.visible || trade.visible || bank.visible
        || social.friendsVisible || hasPendingInventoryOperation || companions.transferPending || cashShop.pending
    }
}
#endif
