# Native RO foundations — active implementation ledger

Scope: A items/professions, B communication/player commerce, C other basic RO
systems. This is not a completion claim. No Simulator or screenshot gate.

Baseline: app 163a4d6 (navigation and world party HP), CI cb3fc33.
Reference: local roBrowserLegacy 2f9a9d6cf5b04a8ac7a44077080772046e15bcb7,
GPLv3. Existing GPL notice retained; native UI uses existing game panels/assets.
Protocol: client and inspected server source PACKETVER 20211103 (RE).
Server source is not a git checkout. Initial binary SHA256:
production edc39d07a519b40d402b2d30d0643587d7eeabe0b7ff53d15ecaae657b5b5206;
rounds test da773822b47435c26dd2d76bd065f911bf0c388b54f59ce517d7ccc2158d9d05.
Different binaries require independent integration evidence.

| Milestone | System | Current verification / remaining work |
|---|---|---|
| A1 | Identify, card composition, arrow/skill selection | Implemented; isolated identify/cancel/card PASS; isolated actual material list and arrow creation PASS |
| A2 | Cart transfers/count/weight | Implemented; isolated roundtrip/invalid quantity/persisted conservation PASS |
| A3 | Refine UI, equipment switch/compare | Implemented; isolated real Vestri NPC refine +1 at 100% and add/remove/full equipment switch PASS; portable tests PASS |
| A4 | Production/Enchant | Server-triggered forging/cooking/skill selection implemented; isolated server recipe selection/forge failure response PASS. Modern NPC Enchant implemented; isolated real group33 NPC perfect/upgrade/reset/cancel and persisted money/material conservation PASS; reset preserves normal cards |
| B1 | Whisper/reply, party/guild chat, friends | Implemented; isolated UTF8 whisper/reply/offline rejection/friend decline/accept/delete PASS; guild live chat PASS; isolated party create/invite/accept/UTF8 chat/leave no further delivery PASS |
| B2 | Guild information/permissions | Implemented; portable identity/permissions PASS; isolated existing-guild fixture invite/decline/accept/notice/unauthorized rejection/positions/chat/expel/disband PASS. Creation blocked by server composite primary key without generated guild_id |
| B3 | Trade item/zeny, vending/buying/signboards | Trade implemented; isolated decline/cancel/two-sided lock/commit/reject/persisted item and zeny conservation PASS; Vending/cart shop creation/cancel/purchase/signboard/close implemented; isolated wrong-shop-ID rejection and persisted item/Zeny conservation PASS. Buying stores implemented; isolated permit/cancel/create/list/over-quantity rejection/sale/delete ACK/close/persisted item and Zeny conservation PASS |
| B4 | Ordinary chat rooms | Implemented separately from exam rooms; isolated normal-account create/private password rejection/join/chat/edit/owner transfer/kick/leave PASS |
| C1 | Bank, RODEX attachments/zeny | Bank implemented and isolated deposit/withdraw/reject/reopen/persisted conservation PASS; RODEX implemented; isolated read/claim/delete/duplicate protection/persisted +2 items +321 Zeny PASS using explicit existing-mail fixture. Sending blocked by server SQLite mail.id NOT NULL (no generated id); begin/cancel/recipient check PASS. Additional zero-Zeny attached-item rejection loses 2500 Zeny postage; outbound send is disabled in this build until backend ID/refund repair is verified. Receiving remains enabled |
| C2 | Pet, homunculus, mercenary | Pet/homunculus/mercenary native UI and commands implemented separately; isolated hatch/feed rejection/feed/name/egg/capture-cancel, hom info/name/autofeed/delete, mercenary contract/info/skills/dismiss PASS. Follow/attack/skill execution, pet evolution recipes/explicit confirmation implemented from current public server DB; isolated real pet evolution rejection/success and persisted materials PASS |
| C3 | Achievement rewards, attendance | Implemented list/update/claim and attendance request/response; portable tests PASS. Live achievement claim blocked by server SQLite timestamp format bug (evidence/rewards-blocker.json); attendance DB loads zero events, no reward calendar invented |
| C4 | Graphics/audio/shortcuts settings | Implemented native sound sliders with live AVAudio mixer/BGM update, 30/60FPS Metal view, effect/fog switches, touch shortcut assignment/clear using existing packet backend. Native compile pending for latest commits; no device audio/visual verification |
| C5 | Reputation/clan/special enchant | Actual production/playable data: 4 clans, 4 reputation entries, 138 enchant recipes and grade data. Modern enchant implemented; clan/reputation/grade-special UI not yet completed. These are not disabled systems. |

Rules: no local optimistic inventory/zeny mutation, no retry of ambiguous monetary
requests, acknowledge server rejects, clear transient windows on disconnect/warp,
bound packet lengths and selections, preserve account/entity identity. Integration
writes only in isolated test accounts/snapshots. No production restarts/deploys,
AI/RL/balance edits, or writes to other players. Build unsigned iPhone app with
Xcode27.2; retain artifact/source/hash provenance and externally sign to install.

Evidence directory: client-build/ro-foundations-20261125 (outside client git).
