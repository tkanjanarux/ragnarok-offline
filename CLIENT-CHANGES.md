# Potion effects and quest log

Branch: client-potions-quests. Based on upstream master (not App Store v2.2).

- Successful use acknowledgements for potion items 501–506 and 569 play color-specific GRF particles and one heal sound. Visual timing is approximate and requires device comparison.
- Quest menu shows server quest titles, objectives, counters, state and expiry. Implements this server's actual 0x9f8/0x9f9/0x9fa/0x8fe/0x2b4/0x2b7 packets. Other protocol revisions are not implemented. Script-only quests without quest packets cannot appear.
- iOS Actions workflow selects Xcode 27.2 on xcode-27 and packages an unsigned IPA. Signing credentials are not included.
- The server's existing Novice Potion EF_HEAL trial remains enabled until the replacement client is verified. Remove that override's specialeffect2 line after validation to prevent duplicate visuals.

Validation pending: macOS compilation, QuestPacketTests, live login/add/kill/delete/relogin, full-HP/last-potion/failed-use effects, Duo layout on the actual device. Local git diff --check passes. No build or visual success is claimed yet.

## iPhone Duo

Xcode 27.2 workflow checks iOS SDK >= 27.1 (Apple fullscreen requirement). Map rendering extends beyond safe areas; controls and dialogs respect safe areas. Layout already observes container width and Metal view bounds dynamically. Actual folded/unfolded testing is still pending.

User clarification: macOS is only the GitHub runner host; deliverable is iOS. Host macOS test step removed from subsequent builds. Latest iOS build has passed and IPA metadata confirms iphoneos27.2 / Xcode27.2. Device gameplay validation remains pending.

## Cash Shop (2026-11-18)
- Added a labeled Cash Shop menu button, server catalogue tabs, item names, quantities, Cash/Kafra balances and optional Kafra-first payment.
- Implements 20211103 open/list/close and single-product purchase requests using existing generated packet structures. Catalogue chunks merge; malformed counts rejected. Pending purchase disables repeat purchases; timeouts never resend.
- Inventory updates use existing item-receipt packets. Server errors shown without optimistic balance deduction. Read-only reference: roBrowserLegacy CashShop flow; implementation written in Swift against rAthena packet layouts (no JavaScript copied).
- Device validation still required: open shop, purchase, insufficient points/weight/slots, reopen and reconnect.

## Original Quest / Cash Shop UX (2026-11-19)

Replaces the temporary rounded-material panels with the renewal RO window layouts used by roBrowser. The oversized Cash Shop entry was an unconstrained `.game` button spanning five grid columns; its style fills both axes. It is now the original `basic_interface/nc_cashshop.bmp` 43×45 icon next to the minimap. Existing bounded `.game` buttons retain their behavior.

- Quest list: 381×466, vertical Active/Feature/Inactive/Cooldown tabs, independent 342×412 details, four-entry yellow/white HUD tracker, per-quest tracking, server-acknowledged active/inactive controls. Feature remains empty, matching this reference implementation. Completed/expired categorization follows its renewal logic.
- Quest metadata: loads `System/OngoingQuestInfoList.lub/.lua` or `data/questid2display.txt` through existing resource/Lua infrastructure, falling back to the server title snapshot. Descriptions, rewards and NPC coordinates are client-resource data, not inferred server rewards. Item markup and reward entries open native item details. Navigation links display text/coordinates; the separate roBrowser Navigation engine is not ported.
- Cash Shop: 723×540, nine tabs, 3×3 catalogue, search/pages, item descriptions, Buy List, quantities/removal, explicit free-point amount and purchase confirmation. Bitmap labels use an image OR a fallback label, avoiding text printed twice. Missing advertisements/payment integrations are not invented.
- Purchase lifecycle: a confirmed cart is sent as one-unit transactions, advancing only after each success. Actual server grant counts vary for stackable and nonstackable products, so treating a batch's first acknowledgement as completion would be incorrect. Partial failures retain unpurchased quantities; timeout locks further purchases until reconnect. Closing the shop does not cancel already-confirmed purchases.
- Shared finite windows fit the viewport and can be dragged within bounds. The tracker scrolls in the space between minimap and action controls. GRF image loading now reloads when asset names change and ignores cancelled loads.

### Reference and evidence

Native baseline `tkanjanarux/ragnarok-offline@ff87ce454971a22069a3fc05ff1a7076799b8e9f`; reference `MrAntares/roBrowserLegacy@2f9a9d6cf5b04a8ac7a44077080772046e15bcb7`. Paths inspected: `src/UI/Components/Quest/Quest.js`, `Quest/QuestCommon.js`, `Quest/QuestHelperCommon.js`, `Quest/Quest/{Quest,QuestHelper,QuestWindow}.{js,html,css}`, `CashShop/{CashShop.js,CashShop.html,CashShop.css}`, and `CashShopIcon/*`. Swift code is a native implementation using existing resource APIs; JavaScript was not embedded.

REA inspected the selected roBrowser JavaScript modules (7 parsed files, no parse failures), evidence `ev_ab5e6c65a95823508728694fc37e10fd2aa520dd1fb8a7fd422123d983b45c54`. REA also inventoried the locally available IPA, evidence `ev_6d58cd9d87adea3fa051178a3f19be73b8fc30445c8d3e428a67353d180f6990`, SHA-256 `b9393861ff9d7c5111b6f9409d72d2e2c8d17f8910f686f36b88ad11251a41f7`. That artifact predates the Cash Shop commit: it is NOT evidence of the changed UI running. The retained bundle is outside the repo at `../client-build/original-ui-rea-evidence.json`. Linux cannot run this iOS artifact; no native screenshot parity is claimed.

### Validation

- PASS: 9 portable tests (7 Swift Testing + 2 XCTest), actual CashShop/QuestLog/QuestRichText models and packet encoding. Reproduce the isolated harness with `python3 scripts/test-original-ui-core.py /tmp/ragoff-ui-checks`, then its documented Docker command. It copies the real packet error enum but excludes the Apple-only streaming decoder; it does not test live sockets or SwiftUI.
- PASS: Swift 6.2 syntax parsing of RagnarokGame, RagnarokScript and RagnarokPackets sources; `git diff --check`.
- ADDED, NOT EXECUTED HERE: native QuestUIState and Lua/TXT metadata tests. These require the native dependency graph.
- UNVERIFIED: Xcode type checking/build, actual GRF coverage and text placement, iPhone Duo compact/expanded layout, active toggle/relog with a live server, item-link touch behavior, and end-to-end purchases. No new IPA has been built. Existing GitHub iOS workflow remains unchanged.
- No commit, push, server restart, database change or deployment in this UI task.

Device acceptance: open all four Quest tabs, toggle active and wait for acknowledgement, track/hide quests, update a kill count, open item/reward details, close list independently of details; open Cash Shop via minimap icon, change tabs/pages/search, add/remove quantities, confirm a small purchase and verify inventory/balance, exercise insufficient points and reopen. Rotate/resize and confirm every close/control remains on-screen.
