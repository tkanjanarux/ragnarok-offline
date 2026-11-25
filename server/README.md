# Deployed native server profiles

The iOS app keeps its existing `swift-rathena` submodule at `eec09e4fdba188acb82d76efff2bea433e438a3d`. Do not change that dependency to rebuild the VPS server. Native server profiles are reproducible overlays of the same pinned source; the Swift package and the shipped iOS application remain unchanged.

Two profiles are intentional. `production` matches the main backend source deployed on 2026-11-25. `playable` adds the exact deployed companion/AI release differences; it is not interchangeable with the production map executable. See `release.json` and `../docs/baseline/deployed-versions.json` for actual deployed binary hashes. Experimental policies are archived under tags, never selected by these build scripts.

## Clone and reconstruct

```sh
git clone --branch main --recurse-submodules https://github.com/tkanjanarux/ragnarok-offline.git
cd ragnarok-offline
python3 server/prepare.py production --output build/server-production --with-runtime-templates
python3 server/prepare.py playable --output build/server-playable --with-runtime-templates
python3 server/prepare.py production --output build/server-production --verify
python3 server/prepare.py playable --output build/server-playable --verify
```

`prepare.py` refuses an existing output directory and verifies every resulting source file against the deployed manifest: 3228 production / 3230 playable files, including the release Makefile. Patches use normalized LF for review, then restore each file's recorded newline format so the original source SHA-256 also matches. No build depends on a temporary worktree or an absolute include path.

## Build on Linux

Install a C/C++ toolchain (GCC with C++17), Make, Python3, Git, SQLite3, OpenSSL and zlib development packages. On Ubuntu/Debian:

```sh
sudo apt-get install build-essential python3 git libsqlite3-dev libssl-dev zlib1g-dev
BUILD_JOBS=2 server/build.sh production
BUILD_JOBS=2 server/build.sh playable
```

Outputs are `build/server-PROFILE/bin/{login,char,map}-server`. The deployed release used x86_64 Linux/GCC; source identity is verified across hosts, but a different architecture/compiler/link ordering need not produce the same binary hash. The playable audit/trip_guard headers and their relative include paths are included. No cached object files are reused from earlier releases.

## Runtime data and migration

`--with-runtime-templates` copies upstream configuration/data/NPC/schema templates plus reviewed gameplay overrides. It does not copy any player DB, account records, network credentials, logs, GRF, or existing executable. Runtime overrides retain the already-deployed settings; they do not introduce rewards or an Attendance event. Network addresses, inter-server credentials, operator accounts and service paths must be supplied privately for a new installation. Nothing here starts, deploys or restarts services.

For an existing backend, use `../scripts/server-closeout/migrate_ids.py` only after stopping all SQLite writers and creating a maintenance backup. It assigns `mail.id` and `guild.guild_id` through SQLite INTEGER PRIMARY KEY AUTOINCREMENT, with transaction/backup/integrity guards. The closeout C++ fixes are already in both reconstructed profiles: do not apply `server-fixes.patch` again.

After accepting new writes, never restore an older full DB snapshot as a routine rollback. Keep the compatible migrated schema when rolling back binaries and reconcile transactions explicitly. The operator's verified backups and deployment reports remain private.

## Attribution

rAthena/swift-rathena source and native modifications are distributed under GPL-3.0; see `LICENSE.rAthena` and the pinned dependency's notices. Third-party dependency files are sourced from that immutable submodule rather than duplicated here. Runtime import/NPC files retain their source notices. The iOS app's roBrowser reference attribution remains in its existing ThirdPartyNotices.
