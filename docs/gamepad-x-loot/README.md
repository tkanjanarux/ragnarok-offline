# X pickup mapping

Branch `gamepad-x-loot`, base `a711731a858930d947938efc98022ec8251376c1`.
Preserves Guild/navigation/HP, server-derived acquisition range and prior controller
safety behavior. Only input mapping, HUD/help/localization, tests and build trigger
change. No server, player/account data, RL, merge or deployment.

## Current mapping

- X alone: pick up nearest known item within the existing one-cell range. Optional
  right-stick press/R3 is the backup. Both emit the same single `.pickup` command.
- The existing pickup pipeline retains explicit monster lock, cancels approach/repeat
  through established stop packets and never walks to distant loot. A resumes attack.
  No item: feedback, no pickup/cancellation. Server validates ownership/capacity/success.
- X alone no longer aliases slot1. LT+A still uses row1 slot1. Y alone stays slot2.
- LT+A/B/X/Y = row1 slots1–4; RT+A/B/X/Y = slots5–8. RT wins both triggers.
  Thus LT+X is slot3 and RT+X is slot7, never pickup.
- Shoulders, A/B/Menu, team D-pad Follow/Assist/Stop/Hunt are unchanged.
- UI labels use the connected profile's actual face/button names (not Xbox names
  forced onto other controllers). R3 appears only when the optional button exists.
  New/updated help has Thai localization. Touch pickup remains available.

## Input safety

The existing reducer resolves modifiers before unmodified face bindings. Button
rising edges, not modifier changes, create actions: releasing/changing a trigger
while X is held cannot turn a shortcut into a pickup or replay a cast. Adding a
trigger to a held plain X cannot cast either. Release/repress the face button.

The reducer emits at most one command per sample. X+R3 together yields one pickup;
trigger+X+R3 uses the X shortcut once, with no delayed R3 command when buttons are
released. Existing action throttling and modal/disconnect/background/map reset
neutral guards remain. R3 suppresses click-induced camera movement as before;
plain X does not suppress the right stick or change its deadzone.

## Verification

Portable Swift6.2:55 tests passed, including actual pickup/combat/skill method seams
and actual PathFinder from the previous range work. Four new mapping regressions
cover X edge/camera, trigger release/switch while holding X, simultaneous X/R3,
and retained Y/slot1 bindings. Lifecycle tests now cover both pickup buttons.
Existing eight-chord, RT precedence, range, skill, lock/cancel and team tests pass.
These are not hardware or live server tests. Full iPhone Xcode27.2 build is enabled
for this branch; final run/artifact/source/SHA256 evidence is in the delivery report.

After external signing/installing:
1. Lock a monster and stand beside loot. Tap X: one pickup request; lock stays.
   A resumes approach/repeat. Hold X: no repeated requests. No nearby loot: feedback.
2. Hold LT or RT and press X: slot3/7. Release only the trigger while keeping X down:
   no pickup. Release X before intentionally pressing it again for pickup.
3. Press X and R3 together: one pickup. Orbit with the right stick while pressing X:
   orbit remains available. R3 still suppresses camera movement while clicked.
4. Try chat/modal, disconnect/reconnect, background and warp while holding X. Input
   must require release rather than replay. Y and all eight trigger slots remain.

No Simulator; no real iPhone/controller or visual verification. No gameplay service
restart/deployment or real-player tests. IPA is unsigned for external signing.
