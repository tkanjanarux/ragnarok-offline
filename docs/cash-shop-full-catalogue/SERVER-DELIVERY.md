# Cash catalogue server delivery — prepared, not live

This is a reviewable activation/rollback plan. It does **not** authorize a restart,
live player write, catalogue reload or production deployment. Implementation and
isolated rehearsal are complete to the explicitly recorded test scope. Request88
is excluded. Physical-device acceptance is unverified.

## Provenance and exact candidate

Client base92eea05 includes recovery5e0d45a; final app source is
`b79d14ea9284753034e14f71e3123e667b03f44f`. `server/prepare.py` reconstructs the two
immutable baseline profiles using the pinned submodule. `server/cash-shop/prepare.py`
applies hash-checked layers in order: cash preflight, exchange/services, item-dialog
lifetime, pet journal, socketless party warp, native capture journal. No force/fuzzy
patching or replacement from a stale `/opt/.../src` is used.

| Profile | Reproduced source files | Map SHA256 | Char SHA256 |
|---|---:|---|---|
| production |3230| `be06b780a8f587d2e5ed8f6dd9c6f046660daf6d3853ee9df430da8668693ff7` | `ec5efbe683b6c0a8f395d9589bd3ff60c1b9df895a635bb0fa6f1cf7af505282` |
| playable |3232| `ea6737d5e333caca749f6f330d9f8301f17af5b2ca453bc353e95065ba5efebb` | `ec5efbe683b6c0a8f395d9589bd3ff60c1b9df895a635bb0fa6f1cf7af505282` |

Both compiled Map+Char from fresh/verified source for **ELF x86_64** and
**PACKETVER20211103**. Full source-tree aggregate hashes are in
[production](production-build-manifest.json) and [playable](playable-build-manifest.json).
Production was **compiled only**, not activated. Only the owned, loopback isolated
fixture used the playable candidate. Do not substitute production Map for playable
Map: the underlying gameplay/AI source profiles differ.

## Clone-to-build procedure

Run from a checkout of this review branch, with Python3/PyYAML, Git, C++ compiler,
make, zlib and SQLite development dependencies. Initialize the pinned dependency:

```
git submodule update --init --recursive
python3 server/cash-shop/prepare.py production --output /path/to/new-production
python3 server/cash-shop/prepare.py production --output /path/to/new-production --verify
python3 server/cash-shop/prepare.py playable --output /path/to/new-playable
python3 server/cash-shop/prepare.py playable --output /path/to/new-playable --verify
python3 server/cash-shop/assemble.py /path/to/new-production --output /path/to/new-production-imports
python3 server/cash-shop/assemble.py /path/to/new-playable --output /path/to/new-playable-imports
```

All output directories must be new. No temporary worktree dependency is required.
For each prepared source directory, build on the target architecture:

```
make -f Makefile.dgx -j2 O=build BIN=bin SQLITE_LIB=-l:libsqlite3.so.0 \
  EXTRA_CXXFLAGS='-Isrc/map -Isrc/map/population_engine' bin/map-server bin/char-server
```

Run native checks before copying any files:

```
python3 scripts/cash-shop/test-pet-journal.py /path/to/new-production
python3 scripts/cash-shop/test-pet-journal.py /path/to/new-playable
python3 scripts/cash-shop/test-assembly.py
python3 scripts/cash-shop/audit-prices.py
python3 scripts/cash-shop/test-card-policy.py
```

The assembler preserves34 existing prices/tabs and the existing item override569;
adds96 custom definitions and123 listed SKUs. It checks reserved-ID/AegisName
collisions against the actual native DB, rejects duplicate/repriced existing cash
entries, and preserves six usable-but-unlisted aliases. No private QA item is emitted.

Final imports are identical across these two candidate profiles:

| File | Expected base SHA256 | Final SHA256 |
|---|---|---|
| item_db.yml | `d73e628891db6060b8f0d79caa467fb042c733024edabd5f4f3ec6ca94c382b3` | `36b510bedc089040af7abe3228c1fb7e8db181d68e4d0d9f137768534c88625b` |
| item_cash.yml | `8629ed428f57e4d2eb8d6315ff3a59d98f0f36ce34691ad390b8b41cebb7bf0a` | `1e76e7252ba3ac35b71ae5baaff5d67f26f77387c41dd3ef8c8757d628b797d5` |

See [production import manifest](production-catalogue-manifest.json) and
[playable import manifest](playable-catalogue-manifest.json). These are **not** a
command to overwrite newer live imports. At activation, compare actual input
hashes and effective import chains again. If different, preserve/review the new
entries and assemble a fresh non-destructive merge, then retest/hash it.

## Changes requiring coordinated activation

The additive SQLite migration is
[`server/cash-shop/native/pet/migration.sql`](../../server/cash-shop/native/pet/migration.sql).
It creates `ragoff_catalogue_pet_journal` only; no account/currency/reward grants
and no reapplication of the older baseline ID migration. Native pet and inventory
IDs use SQLite INTEGER PRIMARY KEY allocation, not fixed IDs or MAX+1.

Matching Map and Char are required. Char advertises capability0x10; Map requires
`(ready & 0x13) == 0x13` for journal delivery. Save barriers and login/session tokens
prevent reuse of a stale response. The journal commits exact before/after inventory
snapshots plus pet identity in one SQLite transaction. Snapshots include native
item-size/slot version checks: **do not migrate them across arbitrary binary ABIs**.
A stale pre-commit inventory save is reconciled; a mixed snapshot is rejected,
never guessed. Successful native capture now uses the same mechanism; RNG and
lure consumption remain native. Matching builds must remain installed while
journal rows are unresolved.

## Activation checklist for a separately approved maintenance window

1. Re-inventory current process executable/cwd/hash, service definitions, effective
   configs/DB paths, Map/Char routing and source provenance for both runtimes.
   Resolve whether they share a DB, including all WAL writers. Check actual online
   sessions using runtime evidence, not only stale DB flags. Preserve other work.
2. Stage matching profile binaries, final imports, migration and manifests in a
   private versioned directory. Record currently installed binaries/config/import
   hashes and a rollback map. Reject unknown source/binary/ABI drift; do not force
   patches or overwrite playable AI with production.
3. Schedule only the necessary activation interruption. Stop **all** writers of
   every effective DB before migration. Use unique, mode0700 backup directories,
   mode0600 files, SQLite backup API/CLI `.backup` (includes committed WAL state),
   and hash/verify each backup with integrity and foreign-key checks. Save existing
   binaries/configs/imports/source manifests and service identity separately.
   Do not use a raw live DB file copy as the only backup.
4. Record table counts, money/item aggregates, pet/inventory IDs and any existing
   journal rows. Apply the idempotent additive migration, compare its table schema
   exactly, and recheck integrity, foreign keys and unchanged existing table counts.
   A conflicting pre-existing journal schema is a blocker, not a reason to drop it.
5. While writers remain stopped, activate matching Char+profile Map, schema and
   verified merged imports together using the established service procedure.
   Restart only affected services. Verify hashes, routes, capability handshake,
   catalogue157 (or reviewed merged count), errors and ordinary account login.
6. Use designated synthetic accounts only for purchase/cancel/reject, pack/menu,
   pet claim/capture/reconnect and transaction-recovery smoke tests. Compare
   Cash/items/pet IDs before/after. No real-player spending, gifts, mail or party
   intrusion. Verify journal reconciliation, map actor placement and original
  34 entries. Open normal writes only after the agreed smoke criteria pass.

The owned isolated rehearsal used schema-only data, two fixture accounts and a
verified SQLite backup. Source/import/binary verification, journal rollback tests,
actual capture/pack failure recovery and final catalogue packets are recorded.
This does **not** stand in for a fresh live backup/online check at activation time.

## Rollback without discarding player writes

Before accepting new writes, a failed activation may restore the verified backup
and matching old binaries/imports while all writers remain stopped. Keep failure
evidence and verify integrity before reopening.

After new writes, **never restore an older full DB**. Disable new purchases/claims,
stop writers, preserve a fresh backup and retain matching guarded Char/Map while
reconciling journal entries. Never drop a nonempty journal or install an old Char
without its save/load guard. A generic old-binary rollback is not safe with pending
rows or new custom items; retain their definitions and produce a compatible rollback
build if needed. Reconcile transactions explicitly so new currency/item/pet data
survives. Catalogue visibility can be reduced without deleting already-owned item
definitions. No automated live rollback has been executed by this task.

## Deliberate exclusions

No companion costume SKU88, economy/reward change, opaque imported item IDs,
RL policy, live DB/log/credential, extracted GRF asset, native build binary or
fixture-only QA probe is committed. No TestFlight/App Store or live server deployment.
Physical iPhone preview, checkout touch performance and controller hardware remain
unverified; the unsigned app requires external signing.
