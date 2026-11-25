# Original RO UI restoration

Review branch: `ui-original-restore`, based on `main` at `bff0484`.
PR #1 (`d68cda8`) was open at review time. None of its engine, inventory,
item-selection or shop files are replaced. This branch does not merge PR #1.
The duplicate `PACKET_ZC_AUTORUN_SKILL` cases in that PR (464 / 628) are
outside this patch; the main base has one case. Recheck when combining PRs.

## Reference and implementation

Compared the five actual roBrowser captures and six user iPhone captures
provided for this task before editing. Reference: roBrowserLegacy
`2f9a9d6cf5b04a8ac7a44077080772046e15bcb7`, GPL-3.0, components Escape,
Bank, Rodex, Achievement, Navigation (HTML/CSS and relevant behavior).
The layout is implemented natively in SwiftUI; no JS runtime, copied GRF,
web wrapper or screenshot mockups are shipped. Garbled reference text and
unknown placeholder names are not reproduced.

- **Options:** 280 wide; 220×20 visible buttons in separate 28-high hit rows,
  spacing 3, vertical padding 20. Character selection, death actions, graphics,
  sound, shortcuts and exit remain connected. Global `.game` style unchanged.
- **Settings:** compact RO tabs, checkboxes, framed inputs and bevel buttons.
  Volume sliders retain native drag/accessibility with the RO blue palette.
  AppStorage keys, audio callbacks and shortcut commands are unchanged.
- **Bank:** 280-wide balance rows and gray amount/actions strip. The coin is
  cropped at runtime from `bank/bg_bank.bmp`, verified locally as 280×136.
  Confirmation, authorization and pending-operation guards are unchanged.
- **RODEX:** logo/header, original GRF refresh/write icons, search across received
  title/sender, Inbox/Unread/Attachments filters, six-entry local pages, details
  and compose. These are local filters, not fabricated server mailbox tabs.
  No unsupported bulk delete/retrieve buttons. Existing send/claim/delete
  confirmations, capabilities and server ACK guards remain intact.
- **Achievements:** rank/points/progress header, category sidebar, completion
  filters, compact list and expandable objective/reward detail. Categories come
  from the exact rAthena database hash already used by AchievementCatalog.
  Summary counts include **received entries**, not an invented full catalogue
  completion total. Unknown IDs remain visible in Other. A reward action still
  needs server completion and is disabled while a claim awaits its response.
- **Navigation:** 320-wide search/filter, current map preview, compact results,
  route/portal instructions and footer actions. Same projections, route core,
  map loading, coordinate validation and cancellation; no automatic walking.

The local GRF contains the two RODEX icons (24×26) and bank background.
`achievement_re` artwork was not found in that local GRF; the achievement
layout uses native RO stripe/bevel/blue-gauge styling instead of invisible
asset-only controls. No graphics or account records are added to Git.

## Layout and interaction review

Restored panels use finite viewport-capped sizes and scrollable bodies, including
compose and route detail. OriginalROPanel opts into a 28-high title interaction
row; the visible title skin remains 17 high. Close targets stay in that row,
so they do not cover search/refresh/actions. Other ClassicGamePanel callers
retain their previous sizing. Options/Settings now receive the same scene
safe-area insets as Bank/RODEX/Navigation. Input windows dismiss their keyboard
by scrolling. No expanded overlay hit regions are used for adjacent buttons.

These are source/layout reviews, **not** device or Simulator measurements.
Small portrait/landscape, notch/home indicator, keyboard, localized wrapping,
disabled controls and touch accuracy still require iPhone acceptance. No
Simulator run or screenshot gate is part of this delivery.

## Validation

- Existing foundation portable suite: 27 passed (includes bank/RODEX/reward
  packet and transaction regression coverage).
- Existing portable navigation suite: 3 passed (obstacles, coordinate clipping,
  directed portals/missing maps and alternative reachable entrances).
- Catalogue extraction: source SHA256 matches the existing names catalogue;
  all 361 ID→group entries come from that database, with no reward changes.
- `git diff --check`; changed-file secret scan.
- Full iPhone Xcode 27.2 build: see task delivery report / Actions run for the
  final source SHA. Portable tests alone do not typecheck SwiftUI.

No gameplay service was restarted, no account was enabled, no real transaction
was sent, and no production or App Store deployment is part of this patch.
