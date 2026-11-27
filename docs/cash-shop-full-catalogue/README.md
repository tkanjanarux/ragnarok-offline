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
