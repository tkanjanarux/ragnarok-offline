# Physical controller — round 1

Base: guild original `2674eea0e185705a8655f637852bc5a0da592d64`, including
navigation `16e8b6a` and HP/party fixes. Guild build45690894899 succeeded.
Separate review branch `gamepad-round1`; no inventory PR merge or server changes.

## Integration

Native Apple GameController extended profile on iOS/iPadOS, not simulated taps.
The main-actor loop samples live profile values every33ms; enumeration handles
preconnected controllers, connect/disconnect and replacement. No action callback
queue is replayed. App-resign/background and disconnect notifications reset the
reducer immediately, and scene/task identity + same-map jump and touch revisions
invalidate input. Resume requires neutral controls. UIKit text input, presented
controllers, game menus/windows, companion management and pending inventory
operations block gameplay. Touch gestures own input until released and the pad
returns neutral. Controller menu/cancel never confirms a transaction.

Left stick uses a radial0.22 deadzone and the same camera-to-grid rotation as the
touch stick. At most five movement requests/second target1–5 tiles beyond the
next movement cell, according to the current server speed, with existing straight-path and request-path checks. No speed
change, local teleport, delayed movement queue or stop opcode. Release/reset stops
issuing requests; the already accepted short path can finish. This is **not an
instant server stop**. Right stick uses clamped elapsed time (50ms maximum),
1.8rad/sec azimuth, 1rad/sec elevation within the existing pi/12...pi/3 limits.

Target candidates come only from known living, non-hidden monsters within12
cells and the current viewport. First acquisition favors current movement/facing;
ID-based ring ordering and lock persist as new monsters spawn. Invalid/vanished/
out-of-view/dead targets clear without automatically attacking their replacement.
The existing world target selector and compact RO HUD identify the lock.

A primary press now uses the same `attackMonster` approach/arrival/DMG_REPEAT
pipeline as touching a monster. One edge starts continuous attacks on that ID;
there is no automatic acquisition/attack after it dies. Moving, B, changing targets,
touch movement, map/lifecycle loss or controller disconnect invalidate an attack
generation, cancel the arrival task and send cancellation only once for that attack.
Cancellation sends CZ_REQUEST_ACT NORMAL target0 (stop attack timer), then one
short WalkToXY to the next known cell (clears server target_to/step_attack via
unit_walktoxy flag4). Server cooldown/status/network rules remain authoritative;
there is no stop acknowledgement or guarantee of instantaneous motion cessation.
Old scenes cannot send cancellation through a new map session. Captured old arrival
callbacks are rejected even when a new attack uses the same monster ID.
Nearby NPC/loot interaction remains bounded, never confirms transactions.

## Mapping

Physical positions below are independent of branding. The HUD displays the
controller's reported localized labels, falling back to position names.

| Input | Action |
| --- | --- |
| Left stick | Camera-relative short-step walk |
| Right stick | Camera orbit/elevation |
| Left / right shoulder | Previous / next monster |
| Bottom face (Xbox A) | Approach + continuous attack / explicit selected NPC / nearby loot |
| Right face (Xbox B) | Cancel targeting, close game menu/guild/help; other transactions use touch |
| Left / top face (Xbox X/Y) | Absolute shortcut row1 slots1/2 (aliases of LT slots1/2) |
| Left trigger + bottom/right/left/top | Row1 slots1–4 |
| Right trigger + bottom/right/left/top | Row1 slots5–8; right wins if both triggers held |
| Menu | Options |
| D-pad up/right/down | Follow/Assist/Stop for the active team |
| D-pad left | Nearby Hunt for the active team |

Shortcuts are bounded by the real list and use the existing item/skill pipeline.
The controller adds passive/unlearned/cast/cooldown/target/range checks; ground
skills are deliberately declined with a touch-controls message, not cast at a
guessed location. One command per press with a150ms minimum action interval;
suppressed presses are dropped, not queued. Slots are absolute, unaffected by the
visible shortcut row shift. No user item IDs are hardcoded.

All four D-pad directions have team scope. The actual RCO1 UI protocol exposes
per-profile Follow/Assist/Stop and `hunt on` for nearby team hunting; it has no
acknowledged `teamfollow` verb. The client first sends existing `teamoff` (or
`hunt off` on the older advertised capability), then serializes follow/assist/stop
for the snapshot of living active profile IDs, or sends `hunt on`. Hunt is the
existing game feature, not camp/Mob/Boss/RL, and the server checks party authority.
Each step waits for the matching sequence, complete ready roster and expected
server success result. Rejection, timeout, roster changes, another command,
modal/lifecycle loss or B cancels the unsent remainder. Already acknowledged
steps remain effective: this is not an atomic team transaction or automatic rollback.
Load the roster through the touch Companions window first; no automatic summons.
Server source evidence: production source.patch `roster_action`, `set_hunt`,
`roster_reply`, plus playable delta; only read, not modified or deployed.

## Tests and acceptance

Portable tests compile the actual reducer/target ring/team plan/attack generation: deadzone/normalization,
axes, send rate, held/edge behavior, trigger conflicts, modal and lifecycle reset,
no replay, bounded camera dt, target stability and invalidation. Existing guild/
foundation and navigation checks remain independent CI jobs. Xcode27.2 builds the
full unsigned iPhone app; no Simulator job or gate.

No physical controller or iPhone/iPad hardware was used to verify this change.
Portable tests and a successful build do not prove device interaction, hardware
labels, latency, visual fit or full live-server integration. No player database,
production restart/deploy or live account testing was performed.

Manual acceptance: externally sign/install the IPA, connect an extended pad,
release all controls, load your active companion roster and confirm Assist mode
using existing UI. In the orc map, walk/turn camera, cycle a visible monster and
press primary once outside attack range. Put your chosen potion in row1 slot1, then press
left face once. Test chord slots, cancel, open chat/Bank, disconnect while moving,
background/foreground and warp; no gameplay should resume until neutral. Confirm
the accepted short step may finish and no held item/skill action repeats.

## API references

- https://developer.apple.com/documentation/gamecontroller/gccontroller
- https://developer.apple.com/documentation/gamecontroller/gcextendedgamepad
- https://developer.apple.com/documentation/gamecontroller/gccontrollerelement
- https://developer.apple.com/documentation/gamecontroller/gcdevice/handlerqueue

No external implementation or proprietary artwork is copied. Existing RO skins
are resolved through the user's resource loader.

## Controls follow-up

Branch `gamepad-round1-controls`, base `be00178` (native build45733383927 passed).
24 portable tests: 19 policy tests and 5 tests compiling the actual MapScene
combat methods with injected movement/packet seams. The latter verify approach,
repeat, single cancellation packets, stale arrival rejection and map identity;
they are not a live server or device test. Run both `scripts/test-gamepad.py` and
`scripts/test-gamepad-combat.py` against the same temporary package, then swift test.

Touch-initiated attacks use the same ownership/generation, so controller B or retarget
also cancels a touch repeat; a fresh touch attack supersedes an old pad arrival.
