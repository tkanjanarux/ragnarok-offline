# Party HP and minimap

## HP beneath party members in the scene

Visible same-map party PCs now get a 60x6-point HP bar, eight points below
their projected feet. It uses the existing Metal bar renderer and RO blue
border/gray background/green health (red below 25%). The sprite's interpolated
world position and terrain height anchor it; the current camera projects it,
with constant point size at every zoom and display scale. The existing owner
HP/SP bar is not duplicated. No bars are added for outsiders or monsters.

Only real party HP/maxHP packets are accepted. Unknown, offline, dead, hidden,
out-of-sight and removed members have no world bar. An unchanged HP sample
does not expire on a timer. Vanish invalidates the old HP sample until a new
server sample arrives, without removing a legitimate same-map minimap dot.

`PartyWorldBars` joins party AID to the visible entity AID. `PartyBarProjection`
keeps the existing billboard shader while converting bar dimensions from view
points to sprite units per camera. `PartyWorldBarTests` covers eligibility,
lifecycle, camera math and actual Metal-rendered pixels on iPhone Simulator.
Three image fixtures use deliberately synthetic avatars and packet values;
they are not live gameplay screenshots or physical-device verification.

The companion server's native HP feed uses the same synthetic account/entity
IDs. A newly attached idle companion may not receive an initial HP packet until
its HP updates or it enters sight again. The client leaves unknown HP blank;
it does not guess or expose unrelated entities. No gameplay server was changed
or restarted. Full source audit, build results, visual evidence and delivery
manifest for this follow-up are in `../client-build/party-world-hp-20261124/`.

## Party window and minimap

The Party window shows HP beneath each member name. Account ID routes party
updates; character ID also guards retained state when a roster is replaced.
Companions are displayed only when present in the server's actual party roster.
The local player's HP uses the existing server-fed character status model.
Unknown HP is shown as `HP —`, never a fabricated full or empty bar. Offline,
dead and other-map states are explicit. HP samples older than 30 seconds are
gray and labelled `Last known HP`; unchanged server HP is not a heartbeat.

The white/red arrow is the local player; cyan dots are online party members,
gray dots are dead members. Position is unknown until supplied by the server.
Negative coordinates remove a dot. Roster map/character changes, offline,
leave, local warp and disconnect invalidate the appropriate cached state.
Stationary positions do not expire on a timer: the server sends changes only.

`MinimapProjection` uses the actual GAT width/height, square bitmap padding and
inverted Y, shared by the map image, player and party dots. Zoom is centered on
the player and clamped at image edges; it is never centered on a party member.
Only the player arrow rotates, not the map or party coordinates. Invalid map
cells are excluded and the viewport clips dots outside the visible crop.
X/Y beneath the map comes from `MapSceneState.playerPosition`, updated from
the player's game grid position during movement/warp. Coordinates occupy a
separate row above zoom controls and participate in the existing HUD obstacle
measurement. The top-right HUD respects trailing safe area; narrow phones
stack the cash-shop button above the minimap.

## Protocol and reference

Inspected local roBrowserLegacy checkout `/tmp/ragoff-falcon.HnoG/reference`,
commit `2f9a9d6cf5b04a8ac7a44077080772046e15bcb7`:

- `src/Engine/MapEngine/Group.js`: account-ID HP routing and negative XY removal.
- `src/UI/Components/MiniMap/MiniMapCommon.js`: GAT padding, Y and arrow orientation.
- `LICENSE`: GPLv3, compatible with this client's existing GPLv3 distribution.

Reference upstream: https://github.com/MrAntares/roBrowserLegacy/tree/2f9a9d6cf5b04a8ac7a44077080772046e15bcb7
Implementation remains native Swift/SwiftUI; no JS dependency was imported.
The existing ThirdPartyNotices entry now records this reference as well.

Checked the actual `companion-dev/src/map/clif.cpp`, `party.cpp` and generated
Swift packets for packet version 20211103:

- `0x080e`: account ID, signed 32-bit current/max HP; area-limited party feed.
- `0x0107`: account ID, signed 16-bit X/Y; same-map party feed, `-1` removes.
- `0x0ab2`: account ID and death flag; revival invalidates old HP until updated.
- Roster/add-member messages carry account and character IDs, map and offline.
- `party_send_movemap` resynchronizes same-map positions; movement timer sends
  changed positions. Population-engine companion placement calls the same
  party HP/XY functions. No server/protocol/AI changes are required.

## Verification and device build

Portable tests compile the actual production model, generated packets and
projection, not substitute mocks:

```sh
python3 scripts/test-party-minimap.py /tmp/party-minimap-tests
docker run --rm -v /tmp/party-minimap-tests:/work -w /work swift:6.2 swift test -j 4
```

Linux checks were followed by the existing remote Xcode 27.2 Actions route.
Run https://github.com/tkanjanarux/ragnarok-offline/actions/runs/45374349184
built the complete unsigned iPhone app successfully and ran all four
`PartyMinimapTests` on iPhone 18 Pro Simulator (iOS 27.0), with zero failures
or skipped tests. Commit `36dc6c127ffc9cd5a3f65f56b242bf2c9f427c15` on
`qa/party-minimap-20261124` contains only this task plus its build workflow.
Unrelated working-tree companion/AI changes were excluded. Production gameplay
and services were not changed. Physical-device visual acceptance remains open.

The verified build evidence and delivery manifest are in
`../client-build/party-minimap-20261124/`. The IPA uses iPhoneOS SDK 27.2,
targets iOS 18+, and requires external development signing before installation.
It is not a TestFlight/App Store release and does not update an installed app
automatically. The app was built with the commands below through Actions;
local lack of Xcode did not block delivery.

On a Mac with the repository's dependencies, run from `client`:

```sh
xcodebuild -project RagnarokOffline.xcodeproj -scheme RagnarokOffline \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build-party-minimap CODE_SIGNING_ALLOWED=NO build
```

For device installation, build with your development signing team in Xcode and
run on the selected iPhone. An unsigned build cannot be installed directly.
Use the existing separate test server, not a restart of playable26900.

World-space party HP follow-up (2026-11-24): commit
`e8651f58a29fac18b305d8aefa372d59295831e7` on the same QA branch adds
screen-projected party bars beneath visible actors' feet. Full Release iPhone
build and all seven native Simulator tests passed in
https://github.com/tkanjanarux/ragnarok-offline/actions/runs/45397338051.
Sixteen portable tests also passed. The new unsigned IPA is
https://76-13-19-77.sslip.io/downloads/RagOff-e8651f5.ipa.
Its HTTPS download matches SHA-256
`7700134608dc6217c9a00ca1e2580441d9267eb25f6c15343e7b4f3b4bc3bdb5`.
Three synthetic production-Metal Simulator images, source routing audit,
manifest and Thai delivery report are in
`../client-build/party-world-hp-20261124/`. These are fixture renderings, not
live gameplay or physical-device verification. Full HUD/safe-area acceptance
on actual devices remains open. An idle companion attached to the party after
spawn can lack its first HP sample until HP changes or sight re-entry; no HP
is fabricated, and no gameplay server changes were deployed.

Acceptance: open Party with a real member and companion; damage/heal/death/
revival must follow server values. Wait 30 seconds without HP updates to see
the last-known label. Move at each zoom level, then warp, leave and logout;
dots must not linger. Check rectangular maps and both map edges. Verify X/Y
against the game's location message, then test portrait and both landscape
orientations on 375-point and larger iPhones, including notch/Dynamic Island,
with expanded menu, status icons, companion HUD and zoom controls. These
device/visual checks have not been run on this Linux host.
