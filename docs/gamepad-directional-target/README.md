# Directional controller targeting

Base: gamepad-round1-controls adb177d, retaining Guild/navigation/HP and controller
reset/stop/shortcut/team controls. Separate branch gamepad-directional-target;
no PR merge, gameplay server changes, RL, accounts, or Simulator.

## One press and explicit lock

Without a lock, point/move the left stick toward a monster, then press primary or
an offensive targeted skill shortcut. The press re-evaluates known candidates
and immediately uses the existing attack/shortcut packet pipeline. Primary uses
the existing approach + repeat attack. Offensive skills require current cast
range and never install a delayed arrival cast. No candidate means feedback and
no attack/cast. Existing nearby loot and explicitly selected NPC interaction remain.

LB/RB or touching a monster is an explicit lock: primary/offensive targeted skills
use it irrespective of facing, while it remains valid. B clears that lock and
cancels arrival/repeat using the existing real cancellation packets. Movement
cancels the current action but retains an explicit lock. No monster names/IDs or
map-specific locations are hardcoded.

There are three separate identities:
- Explicit: scene.selectedTargetID, written by touch or shoulder cycling only.
- Preview: GamepadDirectionalTargets.preview, never written into scene selection.
- Attack: the existing generation-checked attack lease, fixed to the pressed ID.

Preview changes cannot retarget an attack. A dead/hidden/invalid target cancels
without chaining a new attack; another button press is required. A fresh press
may replace the current action. Warp/unload invalidates locally before resetting
coordinates; stale arrival closures cannot send on the new map. Visibility/path
validation runs again immediately before repeat dispatch after an approach.

## Exact selection policy

- Automatic acquisition: Euclidean radius **8 cells**, **40° half-cone** (80° total).
- Explicit/cycle/current-action eligibility: Euclidean radius **12 cells**.
- Candidates: actual known monster entities, alive, non-cloaked/non-hidden/non-invisible,
  inside the current camera viewport. Server combat permissions/immunity remain
  authoritative; the model does not expose a universal attack-permission flag.
- Geometry: existing GAT canMoveStraight gate and findPath(within:1), at most
  **13 path positions**. This is conservative walk-grid visibility, not GPU
  occlusion ray tracing; never route around a wall just for a better score.
- Rank: angle in radians + (distance/8)***0.08**. Direction dominates distance;
  exact ties use entity ID. No behind-the-player fallback.
- Hysteresis: retain the prior *still eligible* preview within **0.06 score units**
  of the best (about 3.44° at equal distance). Leaving the cone clears it immediately.
- Facing: last nonzero camera-relative stick intent, then actual model direction
  when that changes. Camera yaw alone with a released stick cannot rotate the intent.
  Sprite directions follow the existing grid convention: south0 = negative Y,
  north4 = positive Y, west2 = negative X, east6 = positive X.
- A press while the stick is pushed consumes that held direction so it does not
  immediately cancel its own approach. Release then move, or redirect by more
  than **25°**, to move/cancel again. Modal/lifecycle reset clears this latch.

## Indicator and skill behavior

One existing RO selector is rendered, never stacked: preview = static ring at
**0.30 opacity**, active unlocked attack = ring at **0.80**, explicit lock = original
full-opacity ring + gem. Preview has no bobbing gem/name overlay. HUD labels
Preview / Attacking / Locked. Identity/style changes update the marker; ordinary
movement/camera updates do not restart its animation. Dead/hidden markers are
also rejected during render snapshot construction.

Offensive acquisition uses SkillInfoFlag.attack, excluding passive, ground/trap,
support and self-only flags. No skill-name heuristics. A selected player remains
a support target; otherwise support/self skills target the player, never a monster
preview/lock. Ground skills remain touch-only. Unknown flag combinations use touch.
Potion/item shortcuts use the unchanged inventory pipeline and need no target.
Cooldown, learned level, cast, pending, range and modal guards remain enforced.

Mappings are unchanged: LT+A/B/X/Y = row1 slots1–4, RT = row1 slots5–8; RT wins both.
X/Y alone alias slots1/2. D-pad up/right/down/left = team Follow/Assist/Stop/Hunt.

## Checks and device acceptance

Portable policy tests plus extracted actual MapScene combat/skill and PlaySession
shortcut methods test the production logic with movement/packet seams. They are
not a real server or hardware test. Existing Guild/foundation/navigation CI checks
and full Xcode27.2 iPhone build remain enabled without a Simulator gate.

Manual acceptance after externally signing/installing the new IPA:
1. Without lock, face two nearby monsters: faint preview should favor the front,
   not the closer one behind. Primary approaches/repeats with one press; a learned
   offensive targeted shortcut casts once when in range.
2. Shoulder-cycle or touch a monster, face away and use primary/skill: the explicit
   lock should win. Cancel removes the lock; preview must remain faint/unlocked.
3. During repeat, change camera/preview, kill the target, cancel, move away, warp,
   disconnect and background/resume. No retarget/auto-chain or stale arrival.
4. Try heal/buff, potion, ground/passive shortcuts, blocked walls, no candidate,
   both triggers, chat/Bank and team controls. No monster-directed support spell.

No physical iPhone/iPad/controller or screenshot/visual verification was available.
A native build proves compilation/package integrity, not device behavior or latency.
Cancellation is a wire request; accepted movement may finish and network/server
restrictions can delay it. No new stop opcode or instant-stop guarantee.

Vanish/death and hide/cloak/invisible events invalidate the owned action immediately,
before the next controller sample, including entity-ID reuse. Player vanish/death
also resets input generation so immediate resurrection cannot resume held actions.
