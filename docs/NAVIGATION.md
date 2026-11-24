# Navigation guidance

Open the expanded in-game menu and tap the Navigation icon (second row,
rightmost). Search by NPC/monster/map name, select a destination, then close
the window and walk along the yellow minimap route and gold ground markers.
The active route button beneath the minimap reopens the window; its X cancels.
Opening or selecting navigation never sends walk packets. Manual movement
remains in control; moving away from the route recalculates guidance.

The Route tab shows the destination, map name, known coordinates, current-map
preview and each walking portal. A map or monster selection means arrival in
that map, not an invented point or a tracked live monster. NPC destinations
use their client-table coordinates, finishing within two walkable cells.
The coordinate form provides guidance to a user-entered point on the current
map even when no navigation destination tables are available.

## Reference and data

Inspected local roBrowserLegacy checkout `/tmp/ragoff-falcon.HnoG/reference`,
commit `2f9a9d6cf5b04a8ac7a44077080772046e15bcb7`, GPLv3 LICENSE:

- `src/UI/Components/Navigation/Navigation.js`: search and guidance; explicitly
  no automatic walk packets. Also contains private-airship/services features.
- `MapPathFinder.js`: directed walking links type 200 versus services 201–205.
- `NavigationRouteState.js`: active route snapshot.
- `src/DB/Map/NavigationSystem.js` and `src/DB/Bootstrap/DBLoadPlan.js`:
  Navi_Map/Npc/Mob/Link table contracts and GRF paths.

This implementation uses native Swift/SwiftUI/Metal with attribution in
ThirdPartyNotices.txt, without importing JavaScript dependencies or bundling
game navigation tables. Airship, paid/service transport, roBrowser world-map
episode overrides and monster detail sheets are not implemented.

Resources come from the existing local GRF/Remote Client provider:
`data/luafiles514/lua files/navigation/navi_{map,npc,mob,link}_krpri.lub`.
The loader supports Lua source `.lua` fallback and a consistent `krsak` edition
if `krpri` is absent. It does not mix portal graphs from different editions.
Existing Lua 5.1 decoding preserves strings, decoding UTF-8 then Korean as the
client's other Lua metadata loaders do. Sparse numeric rows are supported.
NPC coordinates are columns 6/7 (zero-based); type-200 portal source 6/7,
destination map 8 and landing 9/10. Navi_Mob has no live XY coordinates.

No GRF or navigation tables were found in this workspace or the inspected
artifact-server directories. The user's installed asset set is not known;
data availability and server/GRF episode agreement need live verification.
Missing lists, missing GAT, no portal route and unreachable targets are
reported in the UI. No server database or hidden entity locations are queried.

## Route and lifecycle

NavigationRoute performs full-map BFS with the same GAT walkable categories and
no diagonal corner clipping as the existing movement finder. The packet-bound
32-cell PathFinder is unchanged. Portal routing searches directed arrival
states, validating each segment against GAT, including disconnected entrances
on the same map. It minimizes portal count, not total travel distance or fees.
Search is bounded at 512 arrival states/96 maps with an explicit limit message.
GAT fetches use the configured resource provider; remote fetch/cache policy is
unchanged. Routes describe static walkability, not dynamic player obstacles or
server-specific access scripts/quest gates.

NavigationState runs route work away from the main actor. Cancellation and
generation checks prevent late results from restoring old routes. Scene
updates trim passed cells and recalculate after deviation. Map-change packets
clear old markers before the new scene supplies its confirmed position;
disconnect/logout cancels. Movement is never owned by navigation.

Minimap overlay uses the existing padded-square MinimapProjection (north up,
Y inverted, rectangular-map padding, zoom and clipping). Current-scene gold
markers use MapGrid terrain heights and the production Metal tile renderer;
only the next 100 cells, sampled every three cells, are drawn to bound draw
calls. Full current-map path stays visible on the minimap. Party HP and markers
are preserved, and the owner's marker remains above the guidance line.

The window fits the available viewport with scrollable content and uses the
existing game panel/buttons. Simulator fixture images exercise portrait and
landscape content plus production Metal ground markers. They do not verify
physical-device safe areas, actual game textures or live portal traversal.

## Tests

`NavigationTests` covers Lua table fields, missing/sparse coordinates, service
filtering, long routes, blocked paths, diagonal corners, rectangular projection,
directed portals, disconnected entrances, missing GAT, source-file loading,
successful map transition, movement deviation, warp, cancellation and late
results, plus Simulator UI/Metal fixtures. Existing party/minimap/world-HP tests
run in the same Actions workflow.

Portable core verification:

```sh
python3 scripts/test-navigation.py /tmp/navigation-tests
docker run --rm -v /tmp/navigation-tests:/work -w /work swift:6.2 swift test -j 4
```

The portable harness extracts production metadata types without the Apple/Lua
resource adapter, and compiles the actual NavigationRoute and projection. Lua,
state, resource loading and render tests require the native Simulator job.
