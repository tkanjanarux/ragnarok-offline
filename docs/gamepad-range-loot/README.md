# Controller range and dedicated pickup

Mapping follow-up: [X pickup](../gamepad-x-loot/README.md) supersedes the X/Y alias
and R3-only guidance below; range and pickup pipeline policy remain unchanged.

Review branch `gamepad-range-loot`, base `ce304a2d89045f1bab60a13322a59601578c4f51`.
Includes Guild/navigation/world HP and all prior controller fixes. No merge/deploy.

## Range source and policy

`PlaySession` handles `PACKET_ZC_ATTACK_RANGE` and `CharacterStatus.update(from:)`
stores `currentAttRange`. `attackMonster` already uses this `playerStatus.attackRange`.
Server-side `clif_attackrange` advertises battle_status.rhw.range; status calculation
includes bow/Vulture bonuses. Do not reconstruct a Hunter range or add skill/equipment
bonuses again on the client. Equipment/status packet changes apply to the next sample
and press without caching a weapon-specific limit. Controls help displays the value.

The attack pathfinder uses Chebyshev distance: max(abs(dx),abs(dy)), including
both axes at the boundary. Both soft acquisition and shoulder/explicit/action
validation now include that entire server-advertised square. The old Euclidean
8-cell soft / 12-cell lock approach circles remain as a union, preserving melee
approach usability when the actual weapon range is shorter. These are selection
floors, NOT minimum damage/cast ranges. There is no new guessed Hunter number.
For example a synthetic range14 packet includes offset(14,14) but excludes(15,14);
this is a test value, not a claim about the user's character or live equipment.

Soft aim still requires the front80-degree cone and hysteresis0.06 score units.
Score is angle radians + Euclidean distance/max(8,server range)*0.08; entity ID
breaks ties. Known living, non-hidden, camera-visible monsters only. The existing
straight walk-grid check stays; path checking now asks for a path **to actual
attack range**, not to the monster's feet. The 13-position approach bound no longer
rejects an already-in-range bow shot. Conservative walk-grid LOS can still reject
shots over nonwalkable obstacles; this is not GPU visibility or server immunity data.
Skill casting retains its independently received `SkillInfo.attackRange`, flags,
cooldown and target validation. No server stats/AI/skill range changes.

## Pickup and mapping

R3 means pressing the right stick, not moving it. Only profiles with Apple's
optional `extendedGamepad.rightThumbstickButton` advertise it. Labels come from
that actual button's localizedName with a localized right-stick fallback. Controllers
without the button retain touch pickup; no false R3 capability. New help/feedback
has Thai localization. API reference:
https://developer.apple.com/documentation/gamecontroller/gcextendedgamepad/rightthumbstickbutton

One edge requests the nearest known ground-item ID within Chebyshev1, matching
the existing touch pickup range. Euclidean distance then ID deterministically orders
eligible items. It never walks to distant loot or talks/attacks instead. Successful
request preparation cancels owned approach/repeat via the existing stop protocol
without clearing the explicit monster lock; a new A press resumes attack. No nearby
item leaves the attack alone and gives feedback. Only server ACK/inventory/item
packets establish success; ownership, capacity and denial remain server-authoritative.
No optimistic item removal or automatic retry. Touch pickup remains unchanged.

R3 is edge-only and uses the existing action throttle; held/blocked/lifecycle input
never replays. It suppresses right-stick camera rotation while pressed (normal
0.22 deadzone otherwise), and suppresses a simultaneous movement packet on its
accepted frame. Release re-enables camera orbit. Other simultaneous command edges
retain existing face/shoulder/D-pad priority; R3 does not steal trigger shortcuts.
LT1–4, RT5–8 with RT priority, X/Y1/2, A attack, B cancel, Menu, and team D-pad
Follow/Assist/Stop/Hunt are unchanged. Modal/inventory guards still apply.

## Verification and manual acceptance

Portable Swift6.2:51 tests passed. Includes actual CharacterStatus packet update,
actual PathFinder diagonal/beyond13-cell cases, actual extracted MapScene pickup,
combat and skill methods with injected packet seams, and reducer edge/modal/reset
checks. These are not live server or device tests. Full iPhone Xcode27.2 workflow
is enabled for this branch; delivery evidence records the final result/hash.

After externally signing/installing the new IPA:
1. With a bow equipped, check Controls' server range, test axial and diagonal targets
   at that range using soft+A and LB/RB. Change equipment and compare the new value.
2. A still approaches/repeats; a shorter-range skill must not cast merely because
   the monster can now be acquired. Explicit lock still wins over facing.
3. Lock a monster, stand beside a dropped item and press the right stick. One pickup
   request, lock retained, no camera jump while pressing; release and press A to attack.
4. Hold R3, try no item / distant loot / full inventory / another player's protected
   item, then modal, disconnect, warp and background. No automatic replay/remote loot.
5. A controller without the button must show touch-pickup guidance, not an R3 binding.

No Simulator or real iPhone/controller/visual acceptance, real-player account writes,
server restart/deployment or RL work. IPA is unsigned and needs external signing.
