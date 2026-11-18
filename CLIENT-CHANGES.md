# Potion effects and quest log

Branch: client-potions-quests. Based on upstream master (not App Store v2.2).

- Successful use acknowledgements for potion items 501–506 and 569 play color-specific GRF particles and one heal sound. Visual timing is approximate and requires device comparison.
- Quest menu shows server quest titles, objectives, counters, state and expiry. Implements this server's actual 0x9f8/0x9f9/0x9fa/0x8fe/0x2b4/0x2b7 packets. Other protocol revisions are not implemented. Script-only quests without quest packets cannot appear.
- iOS Actions workflow selects Xcode 27.2 on xcode-27 and packages an unsigned IPA. Signing credentials are not included.
- The server's existing Novice Potion EF_HEAL trial remains enabled until the replacement client is verified. Remove that override's specialeffect2 line after validation to prevent duplicate visuals.

Validation pending: macOS compilation, QuestPacketTests, live login/add/kill/delete/relogin, full-HP/last-potion/failed-use effects, Duo layout on the actual device. Local git diff --check passes. No build or visual success is claimed yet.

## iPhone Duo

Xcode 27.2 workflow checks iOS SDK >= 27.1 (Apple fullscreen requirement). Map rendering extends beyond safe areas; controls and dialogs respect safe areas. Layout already observes container width and Metal view bounds dynamically. Actual folded/unfolded testing is still pending.
