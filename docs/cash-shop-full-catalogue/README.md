# Cash Shop catalogue expansion — work in progress

Base `92eea05a557f6c9c84e166cf7c73031d09fdddaf` includes purchase recovery
`5e0d45af0a5006e860cbf0e892b6d50b1d5c3dea`, guild, navigation, HP and current
controller fixes. This review branch does not deploy either gameplay profile.

[All 88 requirements](COVERAGE.md) and [machine-readable ledger](coverage.json)
remain authoritative about pending work. Candidate definitions are not approval
to sell. No feature is marked ready merely because its script parses.

## Confirmed findings

- Both deployed profiles had 34 identical catalogue entries when read. Their
  import catalogue SHA256 was
  `8629ed428f57e4d2eb8d6315ff3a59d98f0f36ce34691ad390b8b41cebb7bf0a`.
- A synthetic stack of 29,999 followed by two duplicate one-unit cash lines
  charged 20 Cash but granted only one unit. The candidate rejects duplicate
  lines before payment: zero Cash debit, zero items granted in the repeated
  packet test. It also rejects zero quantities and checks totals in 64 bits.
- Item scripts displaying a confirmation menu were freed by `pc_useitem` before
  the response. The scoped lifecycle fix retains a top-level waiting item dialog;
  nested NPC script restoration remains intact. Regression verification is pending.
- Existing Ayothaya costume19557 adds STR1. It is not an eligible stat-free
  cosmetic. Krathong Crown31143 is an actual Thai-themed script-free alternative
  with native metadata and both sexes' sprite/ACT assets found locally.

## Implementation underway

67 explicit supply bundle variants cover part of the ledger. They grant fixed
contents through `catalogue_exchange`, with positive/unique components, exact
plain-stack identity, weight and slot preflight, and delayed voucher consumption.
Pet eggs, rentals, GUID items and equipment are deliberately outside that primitive;
those systems require their own lifecycle evidence before being offered.

Costume try-on uses the native composed-sprite renderer on the current character,
with four viewing directions and no purchase/equip packet. Missing advertised
parts fail closed instead of showing an unchanged character as a successful preview.
The selected cosmetic is shown without other headgear/garments/weapons to make its
appearance unambiguous. Actual iPhone visual acceptance remains unverified.

## Reproduce candidate sources

Initialize the pinned dependency with `git submodule update --init --recursive`.
Then run, with a new empty output path:

```
python3 server/cash-shop/prepare.py playable --output /path/to/new-candidate
python3 server/cash-shop/prepare.py playable --output /path/to/new-candidate --verify
python3 server/cash-shop/generate.py --output /path/to/new-review-definitions
```

Use `production` to reconstruct its separate base; never replace playable with a
production map binary. Preparation verifies every base file and overlay hash.
Candidate definitions must be merged with existing imports, never replace them.
Build the native server for the destination architecture (the development host
is ARM64; the isolated VPS is x86_64). `Makefile.dgx` uses system SQLite:

```
make -f Makefile.dgx -j2 O=build BIN=bin SQLITE_LIB=-l:libsqlite3.so.0 \
  EXTRA_CXXFLAGS='-Isrc/map -Isrc/map/population_engine' bin/map-server
```

The temporary validation instance is loopback-only and uses a schema-only database
with two synthetic accounts. Credentials, database snapshots, raw logs, GRF files,
extracted art and temporary Lua vendor adapters are excluded from this branch.

## Attribution and limits

Server modifications use rAthena's existing GPL license. GRF assets are resolved
locally; no extracted art is added. roBrowserLegacy's GPL3 source at reference
commit `2f9a9d6cf5b04a8ac7a44077080772046e15bcb7` informs layout/resource auditing;
no web runtime is added to the iOS app. No Simulator or hardware testing is claimed.

Deployment is pending review, full integration evidence and a separate activation
step. No live accounts, balances, inventories, gameplay services or RL policy were
modified by this work.

## Milestone 2 evidence (still not final sale readiness)

- [67 bundles](bundle-packet-evidence.json): buy/debit once, cancel, exact fixed
  contents and real reconnect; five additional inventory/weight/menu cases are in
  [edge evidence](bundle-edges-evidence.json).
- [Six initial services](services-evidence.json): skill/stat/full reset, Gym,
  repair and rename-credit activation. Reset refunds actual spent points and
  retains quest/permanent/unspent bonuses. [Rename](rename-evidence.json) also
  tests duplicate/invalid names, configured party/guild rejection, one-credit
  consumption and reconnect. Character selection now uses the actual 0x08fc/0x08fd
  protocol, with pending/timeout/connection identity guards.
- [Three style variants](styles-evidence.json): confirmed changes, cancellation
  and reconnect. Local assets support human classic/rebirth hairstyles1–42,
  hair colours0–8 and common clothes colours0–3. Server bounds are also checked;
  unsupported jobs/styles keep the voucher. No persistent preview mutation.
- [24 costumes](costumes-evidence.json): exact item purchase/equip/persist/reconnect;
  no item/equip/unequip script, base attack/defense/slots or matching live item
  combos. Initial packet checks cover MaxHP/MaxSP, not all six stat packets yet.
  Real GRF collection images were inspected privately for the added cape/backpack/
  wing/halo variants. This is not native-app/device visual verification.
- [Twelve consumables](consumable-effects-evidence.json): actual HP/SP recovery,
  six +5 stat foods and MaxHP/MaxSP changes with single consumption and saved
  status/reconnect. Combat multipliers, duration boundaries and eligibility cases
  still require their own tests; those flags are not silently marked complete.
- [Card removal](card-removal-evidence.json) follows the existing Wise Old Woman
  probabilities, Zeny and material costs, plus one voucher per completed attempt.
  Synchronous preflight prevents partial card grants; item identity/refinement/
  other attributes are retained. Cancel, insufficient Zeny/materials, full bag
  and a successful removal/reconnect passed. Every probability boundary is tested
  from the production function; random failure inventory branches remain pending.

Companion fashion88 is excluded: the current server explicitly rejects costume
and shadow slots. No stat-bearing substitute or fake appearance SKU is offered.
Other incomplete requirements remain in the 88-row ledger; this milestone does
not claim that pets, companion supplies, all utility services or all item effects
are complete. All candidate sale flags remain false until their required evidence
and deployment review are complete.

## Milestone 3 in progress: pets and remaining supply variants

There are now 83 explicit supply variants, 13 service/voucher variants, 25 costume
candidates and eight utility/accessory entries. These are still review candidates;
the ledger does not yet mark the full catalogue ready to sell. Existing deployed
entries remain unchanged. Sixteen new bundle packet tests are in progress.

Three pet packs use real Poring/Spore/Lunatic eggs with their correct food (531/537/534).
[Packet evidence](pet-packs-evidence.json) covers each purchase, one Cash debit,
cancel, atomic egg/food/voucher exchange, hatch, feed, accessory equip, rename,
reconnect and return-to-egg. [Six failure cases](pet-edges-evidence.json) cover full
inventory, weight, food stack cap, disconnect at confirmation, repeated use and an
injected SQLite journal-insert failure. None consumed a rejected voucher or left an
orphan pet. Twelve native tests execute the production SQL adapter against isolated
in-memory SQLite: replay, stale inventory, ambiguous snapshot, recovery, identity,
stack merge and rollback at pet/journal insertion. Run against a prepared source:

```
python3 scripts/cash-shop/test-pet-journal.py /path/to/new-candidate
```

Pet accessories replace ACT while retaining the actual species SPR, following
roBrowserLegacy PetAction/Pet.js at the documented commit. Five local accessory
ACT/SPR pairs passed native file decoding and frame-index checks. This is not an
app screenshot or hardware visual test. Actual packet equip has so far covered
Poring, Spore and Lunatic; the remaining species still require integration.

### Pet delivery activation and rollback requirements

Apply `server/cash-shop/native/pet/migration.sql` only with all effective SQLite
writers stopped and a verified SQLite backup including WAL contents. It adds one
journal table, no rewards or player grants. Char and Map must both use the matching
prepared profile. Map refuses delivery without Char's barrier capability and the
journal table. Pet and inventory IDs come from SQLite INTEGER PRIMARY KEY, not
MAX+1. The journal records exact before/after inventory snapshots with native
item-size/slot version checks; it is not portable across arbitrary server ABIs.

A save of the old snapshot is reconciled to the committed delivery; a mixed snapshot
is rejected rather than guessed. Load acknowledges only the committed inventory.
Never drop a nonempty journal or downgrade to a Char build lacking its guard while
entries remain. Before rollback, disable catalogue purchases/claims, stop writers,
reconcile pending entries using the matching build and verify inventory/pet IDs.
After new writes, do not restore an old database and discard those writes. This is
an activation plan only: production/playable have not been changed.

[Fourteen additional status-item cases](status-items-evidence.json) verify actual
cures, resist/converter/status application, single consumption, saved statuses and
speed expiration as applicable. They do not measure combat damage, drop probability
or EXP multipliers. Those effect/eligibility cases remain separate pending work.

Milestone 2 source `f6a3c781ecebbdc62cf9cd64c532d272b035b08c` passed Xcode27.2 in
[run45947045225](https://github.com/tkanjanarux/ragnarok-offline/actions/runs/45947045225).
Its downloaded unsigned IPA SHA256 is
`31f6aee6d196d891ab64b577249ce3b8418fcb13b32e3d8b524b41ecee5f032d`.
It does not include the new pet-rendering work; a later build is required.

### Subsequent isolated evidence

- All 16 added variants passed buy/debit once/cancel/open/exact contents/reconnect,
  bringing tested bundle transactions to 83. Effect readiness remains per item.
- All 25 costumes passed purchase/equip/persist/reconnect with MaxHP, MaxSP and all
  six base+bonus stat parameters unchanged. The two garment metadata overrides
  resolve actual local icons; [87 native items](native-item-audit.json) have all
  174 icon/collection BMP files verified. No extracted images are included.
- [Six taming species](taming-evidence.json) succeeded using their native unchanged
  capture chances. Native cancellation consumes a lure; it is not a free preview.
  Capture-success/disconnect recovery is not covered by that test.
- [Six pet species](pet-species-evidence.json) passed no-food rejection, correct
  food-pack purchase/feed, accessory equip, Loyal bonus and reconnect. These effect
  tests explicitly seed synthetic owned eggs/pets at Loyal intimacy; native capture
  is tested separately. The extra Drops SPR/backpack ACT pair also passed native
  parsing/frame-index validation. None is an iPhone rendering claim.
- [Utilities](utilities-evidence.json): dead-only Siegfried resurrection, repeated
  resurrection consuming one token, Magnifier identification, and all four arrow
  crafting materials with exact native output and stale-selection rejection.
- [Five companion roles](companion-supplies-evidence.json) passed real pack purchase,
  opening, Give Supplies transfer and native HP/SP potion consumption; Stop pauses
  consumption. The actual server has four recruitable careers. The five-role set
  is Knight Puller, Knight Spear, Hunter, Wizard and Priest, not a nonexistent
  Assassin companion. This does not change player Assassin Supply (request81).
  Arrow/gem combat consumption and transfer permission edges remain pending.

Milestone3 `05f32a9e74c05eaa6e973867fe994df4c62f63ba` passed all five workflow jobs in
[run45951620214](https://github.com/tkanjanarux/ragnarok-offline/actions/runs/45951620214).
Downloaded unsigned IPA SHA256:
`3fdca0f786c12b6e343707f4a2010d93a162e31d496e0abd6ed4c4a81f816219`.
It includes pet accessory rendering, but predates the corrected companion role
labels; it is an intermediate artifact, not the final catalogue delivery.
