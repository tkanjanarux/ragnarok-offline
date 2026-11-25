# Server closeout: review and controlled deployment

ยังไม่ได้ deploy production หรือ playable. ทดสอบเฉพาะ `/opt/ragoff-ui-foundations-20261125` (loopback 36910/36131/35131), synthetic AID2100001/2100002, CID160001/160002.

## Scope

- `src/char/int_mail.cpp`: atomic mail/attachments savepoint; rollback and clear ID on failure. Savepoint permits achievement reward + mail to share a transaction.
- `src/map/mail.cpp`: validate title before debit; 64-bit fee arithmetic; refund postage even when attached Zeny is zero.
- `src/char/int_guild.cpp`: creation transaction includes guild/member/positions/skills; rollback any failed write; reject another creation for a character already in a guild.
- `src/map/guild.cpp`: consume Emperium at inventory index zero as well as later indices.
- `src/char/int_achievement.cpp`: correct literal SQLite strftime format; reward marker and mail commit together; notify only after commit; check full 32-bit item ID.
- `src/map/clif.cpp`: announce outgoing-mail capability during successful begin-draft ACK. Native client consumes the marker and keeps Send disabled on older servers. This is not a reward/balance change.
- `migrate_ids.py`: rebuild only `mail` and `guild` with SQLite INTEGER PRIMARY KEY AUTOINCREMENT; preserve existing IDs/columns/indexes/triggers; refuse duplicate/out-of-range IDs, unexpected schema or failed integrity/FK check. No MAX+1.

Source snapshot is from `/opt/ragoff-server`; playable has a different original map binary. Do not overwrite playable with this test binary. Apply reviewed patch to its actual source/build provenance and rebuild there in a separate directory. Exact input/output hashes are in `server-source-manifest.json`. rAthena source retains its GPL copyright/license; no AI/RL changes are in the patch.

## Review before maintenance

1. Confirm intended runtime root, executable hashes, PACKETVER20211103, effective DB path and config. Compare all six base file hashes using `python3 apply_source_patch.py SOURCE_ROOT`. Any mismatch requires a scoped rebase/review; do not force the patch over another session's work.
2. Review patch and integration evidence. Check active users and agree a maintenance window with the owner; this delivery does not authorize disconnecting users.
3. Build patched source in a separate directory. Existing DGX makefile has no header dependency tracking; use a fresh build. On this x86_64 test VPS the SQLite link path was `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0`; do not copy an architecture-specific path blindly. Build login only if its source/config requires it; login was not changed here.
4. Before migration, stop all writers to the intended database under the approved maintenance procedure. Record process identities and service configuration, preserve existing binaries/config, and back up the database using SQLite backup API (including WAL contents), with restrictive permissions. Do not copy a live DB file without WAL handling.
5. Run `python3 migrate_ids.py DATABASE UNIQUE_BACKUP_PATH --writers-stopped`. Existing backup paths are refused. Verify integrity and unchanged existing IDs before activating binaries.
6. Install matching char/map binaries and schema together, start through the existing service procedure, then smoke-test using designated accounts. Do not use player mail/items/money for tests. A missing/old backend keeps outgoing mail disabled in the new client.

## Rollback

- Before accepting user writes: stop the same writers, restore original binaries/config and the verified migration backup via SQLite backup API, verify integrity, then start using the existing procedure.
- After accepting writes: **do not restore the old full DB snapshot**, which would discard new mail/items/characters. Stop writes and assess first. The INTEGER primary keys remain compatible with old INSERT statements; a binary rollback can retain the migrated schema. Keep outgoing mail disabled if reverting the map fix. Any data repair requires explicit reconciliation of new transactions.
- Source patch rollback: `git apply --reverse --check server-fixes.patch` then reverse only if current patched hashes match the manifest; otherwise review changed hunks. The helper's source backup is separate from the DB backup.

## Limits

Tests cover explicit server rejection/SQL failure, protocol duplicates and ordinary disconnect/reconnect. They are not a process-kill/power-loss fault-injection certification for the existing map/char distributed inventory-save architecture. No production runtime has been updated. Attendance has only commented historical sample rewards and no active imported schedule; the owner must define a real event before claiming becomes available. No schedule or economy was invented.
