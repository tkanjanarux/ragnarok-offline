# Guild original UI

Review branch `ui-guild-original`, based on `ui-navigation-polish` 16e8b6a.
The current main bff0484 and the inventory PR remain independent. No merge or
runtime changes are part of this task.

## Reference

roBrowserLegacy 2f9a9d6cf5b04a8ac7a44077080772046e15bcb7, GPL-3.0:
`src/UI/Components/Guild/Guild.{html,css,js}`, with the guild reference notes
for member view, grade changes and the legacy info tab. The actual reference is
a 400×317 window with a title strip, tab band, separate content pane and button
bar. Guild screenshots were **not** supplied: the earlier comparison captures
show other windows. No account was enabled or used to obtain a guild image.

The SwiftUI layout is implemented locally; no JS dependency or proprietary
artwork is bundled. Local GRF lookup verified titlebar_mid, btnbar_mid2,
grp_online, skill_up_a and checkbox_0/1 assets. These resolve through the game's
existing resource loader. Do not commit the GRF or extracted artwork.

## Changes and mobile adaptation

- A compact create/invitation view for guildless players; separate Info, Members,
  Position, Guild Skill and Guild Notice tabs for guild members. The window is
  at most 400×390 (230 tall while guildless), with reserved touch rows instead of
  inflating every visual button. Content scrolls inside the finite safe viewport.
- Uses the continuous titlebar and disjoint drag/close regions from 16e8b6a.
  Navigation, HP, packet handlers and transaction reducers are unchanged.
- Info contains server summary, a native-size 24×24 emblem, EXP, alliance/opposition
  and the existing disband action with a separate name confirmation field.
- Member table keeps real account/character identity and stable online-first
  ordering, with position, job, level, tax and contribution. Horizontal scrolling
  preserves readable columns on narrow screens; selection exposes existing
  actions below the table. No invented map, portrait or last-login value.
- Positions show actual rights/tax to members, and an inline RO editor to masters.
  The editor stays open after submission and reloads server values on result;
  timeout keeps the existing transaction guard rather than inviting a duplicate.
  Checkboxes use GRF skin; the notice editor is master-only, values otherwise.
- Existing skill learn/use, alliance, invitation, emblem, leave/expel and notice
  callbacks remain. No new protocol/server change. Empty datasets state that no
  information has arrived, not a fabricated roster or skill tree.
- Confirmation/file-picker actions verify guild context and current pending state.
  Member actions resolve the live member by account + character ID and recheck
  rights/rank, rather than using a stale captured row. Guild/role changes clear
  editing context. Text inputs honor existing UTF-8 byte limits and NUL rejection.
- Notice updates populate an untouched editor when packets arrive; unsent edits
  survive unrelated refreshes. No optimistic success is displayed.

## Verification and limitations

Portable foundation suite: 27 existing tests + 6 guild presentation regressions.
Navigation suite: 13 tests retained, including shared chrome/hit-area geometry.
The full iPhone workflow uses Xcode27.2 and has independent portable-check jobs;
there is no Simulator job or gate. Build result, commit/artifact hashes and exact
run URL are recorded in the task delivery report outside the repository.

No Simulator, physical iPhone visual/touch/keyboard verification, or live guild
transactions were run in this UI task. UI layout is source-reviewed; portable
checks do not certify rendered appearance or full server transactions. Existing
server ACK/reject/timeout behavior is retained, not newly integration-certified.
Expel History and member portraits are not implemented in this client and no
placeholder tab is offered. The reference's optional tendency/tax-point display
is not added. File import remains BMP-only (24×24, existing 8/24-bit validator),
not the reference browser's wider file-format support. No server bug is claimed.
