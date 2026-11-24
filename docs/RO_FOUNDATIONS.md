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
| A1 | Identify, card composition, arrow/skill selection | Implemented; isolated identify/cancel/card PASS; arrow live test pending |
| A2 | Cart transfers/count/weight | Implemented; isolated roundtrip/invalid quantity/persisted conservation PASS |
| A3 | Refine UI, equipment switch/compare | Implemented server-triggered refine, switch and comparison; portable protocol tests PASS; live test pending |
| A4 | Production/Enchant | Server-triggered forging/cooking/skill selection implemented; live crafting and enchant audit pending |
| B1 | Whisper/reply, party/guild chat, friends | Implemented; isolated UTF8 whisper/reply/offline rejection/friend decline/accept/delete PASS; party/guild live test pending |
| B2 | Guild information/permissions | Implement after member/session identity audit |
| B3 | Trade item/zeny, vending/buying/signboards | Trade implemented; isolated decline/cancel/two-sided lock/commit/reject/persisted item and zeny conservation PASS; vending/buying/signboards pending |
| B4 | Ordinary chat rooms | Implemented separately from exam rooms; isolated normal-account create/private password rejection/join/chat/edit/owner transfer/kick/leave PASS |
| C1 | Bank, RODEX attachments/zeny | Bank implemented and isolated deposit/withdraw/reject/reopen/persisted conservation PASS; RODEX pending |
| C2 | Pet, homunculus, mercenary | Implement standard RO systems separately from custom companion |
| C3 | Achievement rewards, attendance | Existing incoming achievement packets ignored; validate loaded server data |
| C4 | Graphics/audio/shortcuts settings | Audit existing backend before enabling controls |
| C5 | Reputation/clan/special enchant | Inspect actual enabled data/NPC; not marked disabled from missing client UI |

Rules: no local optimistic inventory/zeny mutation, no retry of ambiguous monetary
requests, acknowledge server rejects, clear transient windows on disconnect/warp,
bound packet lengths and selections, preserve account/entity identity. Integration
writes only in isolated test accounts/snapshots. No production restarts/deploys,
AI/RL/balance edits, or writes to other players. Build unsigned iPhone app with
Xcode27.2; retain artifact/source/hash provenance and externally sign to install.

Evidence directory: client-build/ro-foundations-20261125 (outside client git).
