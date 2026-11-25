-- Additive, staging-only migration. No real login/char/inventory rows for AI.
BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS ragoff_companion (
 id INTEGER PRIMARY KEY AUTOINCREMENT CHECK(id>0 AND id<95000000),
 owner_account INTEGER NOT NULL,
 owner_char INTEGER NOT NULL,
 job INTEGER NOT NULL CHECK(job IN (7,8,9)),
 name TEXT NOT NULL,
 level INTEGER NOT NULL CHECK(level BETWEEN 1 AND 999),
 job_level INTEGER NOT NULL DEFAULT 1 CHECK(job_level BETWEEN 1 AND 999),
 base_exp TEXT NOT NULL DEFAULT '0', job_exp TEXT NOT NULL DEFAULT '0',
 hp INTEGER NOT NULL DEFAULT -1 CHECK(hp>=-1), sp INTEGER NOT NULL DEFAULT -1 CHECK(sp>=-1),
 gems INTEGER NOT NULL DEFAULT 0 CHECK(gems BETWEEN 0 AND 20),
 status_points INTEGER NOT NULL DEFAULT 0, skill_points INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ragoff_companion_owner ON ragoff_companion(owner_account,owner_char);
PRAGMA user_version; -- Do not overwrite the existing engine's schema version.
COMMIT;
