# Navigation / titlebar polish

Base: `ui-original-restore` at `2447080`. This follow-up preserves that UI and
its transaction/packet guards; it does not merge the inventory PR or deploy.
Reference: the two new iPhone feedback photographs, roBrowserLegacy
`2f9a9d6cf5b04a8ac7a44077080772046e15bcb7` (GPL-3.0),
`Renderer/Effects/NavigationFootstep.{js,vs,fs}` and
`UI/Components/Navigation/Navigation.{html,css,js}`.

## Changes

- **Continuous titlebar:** ClassicGamePanel now draws one full-width GameTitleBar.
  It no longer shortens that view and fills the right end with another BMP at
  a different vertical origin. Trailing title padding reserves the close area.
  Separate drag and close hit regions share the same reserved header row;
  content starts below both. The visual skin remains 17 logical points tall.
  Shared callers that previously used a 44-point close target over a 17-point
  row now reserve that target above the content, including scaled panels. The
  caller's original content height is preserved; the full window scales to fit
  so fixed Cash Shop/Quest/Party footers are not cropped by the added clearance.
- **Directional ground markers:** dedicated navigation snapshot and Metal renderer,
  separate from tile selection/combat ground indicators. Load the user's existing
  `navigation_interface3/navi_grid1_4.tga` (+Y image) and rotate ground quads along
  the route. Local GRF inspection confirmed all eight 32×32 navi_grid1 images.
  Resource decoding and model/view/projection use the existing pipelines. If the
  texture cannot load, draw a yellow arrow with shaft/head/dark outline, following
  the reference fallback. No pulsing alpha or frame-time animation is introduced.
  Markers use the terrain's corner heights and render before sprites with depth
  testing; they are not camera-facing SF Symbols. Mesh buffers are rebuilt only
  when marker identity/position/direction/terrain changes, not each render frame.
- **Stable route progression:** NavigationGuidance stores the full route and a
  progress cursor. Every-third-point markers keep their original route/index IDs;
  only passed markers are removed. On-path walking starts no new route search.
  Off-path updates coalesce for 180 ms and use the latest position, with at most
  one worker in flight. A same-map/same-destination route stays visible while a
  replacement is pending, including an explicit Recalculate. The new route is
  published in one MainActor turn only if it contains the latest position.
  Cancel, destination change and warp clear markers immediately and invalidate
  old async results, even if the worker ignores cancellation.
- **Minimized navigation:** original RO title skin, restore/close GRF glyphs and
  a striped destination row replace the black SF-symbol toolbar. Open and cancel
  still use independent 44×32 targets with a 4-point gap and accessibility labels.
  No additional actions or movement packets were added.

## Validation

`scripts/test-navigation.py` now compiles the actual presentation-independent
NavigationGuidance and arrow/chrome geometry on Linux, rather than testing only
routing. Tests cover stable marker positions/identity, no on-path recalculation,
pending reroute continuity, coalescing to the latest position, explicit recalculate,
late-result rejection on cancel/destination/warp/return-to-route, new-map activation,
arrival cleanup, all eight arrow directions/UV orientation/terrain heights, and
non-overlapping header regions for compact/wide/scaled panel families. Existing
obstacle/portal/missing-map tests remain included.

Run:

```sh
python3 scripts/test-navigation.py /tmp/navigation-tests
docker run --rm --network none -v /tmp/navigation-tests:/work:ro -w /work swift:6.2 swift test --scratch-path /tmp/build
```

The iPhone workflow builds with Xcode 27.2 and runs these portable checks as a
separate job. No Simulator job is added. Full build, artifact/source hashes and
current results are recorded in the task delivery report. The prior restore build
run45644280441 has subsequently succeeded; its previously queued status was not
an indication of a missing runner.

## Acceptance limits

No new iPhone rendering/touch screenshots or Simulator verification were performed.
The reference photographs establish the reported defects; source, geometry tests,
and an iPhone build do not certify the final appearance on a physical device.
GRF images remain private resources: only paths and code are committed. Direction
uses the immediate next path point; a turn can rotate the next arrow independently
without shifting all remaining markers. No backend, account, AI/RL or economy
changes are part of this work.
