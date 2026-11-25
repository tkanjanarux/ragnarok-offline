BEGIN IMMEDIATE;
CREATE TABLE ragoff_companion_new (
 id INTEGER PRIMARY KEY AUTOINCREMENT CHECK(id>0 AND id<95000000),
 owner_account INTEGER NOT NULL,
 owner_char INTEGER NOT NULL,
 job INTEGER NOT NULL CHECK(job IN (7,8,9,11)),
 name TEXT NOT NULL,
 level INTEGER NOT NULL CHECK(level BETWEEN 1 AND 999),
 job_level INTEGER NOT NULL DEFAULT 1 CHECK(job_level BETWEEN 1 AND 999),
 base_exp TEXT NOT NULL DEFAULT '0', job_exp TEXT NOT NULL DEFAULT '0',
 hp INTEGER NOT NULL DEFAULT -1 CHECK(hp>=-1), sp INTEGER NOT NULL DEFAULT -1 CHECK(sp>=-1),
 gems INTEGER NOT NULL DEFAULT 0 CHECK(gems BETWEEN 0 AND 20),
 status_points INTEGER NOT NULL DEFAULT 0, skill_points INTEGER NOT NULL DEFAULT 0
);
CREATE TEMP TABLE companion_old_sequence AS SELECT seq FROM sqlite_sequence WHERE name='ragoff_companion';
INSERT INTO ragoff_companion_new SELECT * FROM ragoff_companion;
DROP TABLE ragoff_companion;
ALTER TABLE ragoff_companion_new RENAME TO ragoff_companion;
UPDATE sqlite_sequence SET seq=max(seq,coalesce((SELECT seq FROM companion_old_sequence),0)) WHERE name='ragoff_companion';
DROP TABLE companion_old_sequence;
CREATE INDEX ragoff_companion_owner ON ragoff_companion(owner_account,owner_char);
CREATE TRIGGER IF NOT EXISTS ragoff_companion_policy_cleanup AFTER DELETE ON ragoff_companion
BEGIN DELETE FROM ragoff_companion_policy WHERE profile_id=OLD.id; END;
CREATE TRIGGER IF NOT EXISTS ragoff_companion_gear_protect BEFORE DELETE ON ragoff_companion
WHEN EXISTS(SELECT 1 FROM ragoff_companion_gear WHERE profile_id=OLD.id)
BEGIN SELECT RAISE(ABORT,'Return companion equipment before releasing profile'); END;
CREATE TRIGGER IF NOT EXISTS ragoff_companion_growth_cleanup AFTER DELETE ON ragoff_companion
BEGIN DELETE FROM ragoff_companion_growth WHERE profile_id=OLD.id; END;
CREATE TRIGGER IF NOT EXISTS ragoff_companion_supply_protect BEFORE DELETE ON ragoff_companion
WHEN EXISTS(SELECT 1 FROM ragoff_companion_supply WHERE profile_id=OLD.id AND amount>0)
BEGIN SELECT RAISE(ABORT,'Return companion supplies before releasing profile'); END;
CREATE TRIGGER IF NOT EXISTS ragoff_companion_supply_cleanup AFTER DELETE ON ragoff_companion
BEGIN DELETE FROM ragoff_companion_supply WHERE profile_id=OLD.id; END;
CREATE TRIGGER IF NOT EXISTS ragoff_companion_preset_cleanup AFTER DELETE ON ragoff_companion
BEGIN DELETE FROM ragoff_companion_preset WHERE profile_id=OLD.id; END;
COMMIT;
