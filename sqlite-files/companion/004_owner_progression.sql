-- Additive M9.1. Keep the legacy progress snapshot for targeted rollback, never restore the whole player DB.
BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS ragoff_companion_legacy_growth AS
 SELECT id AS profile_id,job,level,job_level,base_exp,job_exp,status_points,skill_points FROM ragoff_companion WHERE 0;
CREATE UNIQUE INDEX IF NOT EXISTS ragoff_companion_legacy_growth_id ON ragoff_companion_legacy_growth(profile_id);
INSERT OR IGNORE INTO ragoff_companion_legacy_growth SELECT id,job,level,job_level,base_exp,job_exp,status_points,skill_points FROM ragoff_companion;
CREATE TABLE IF NOT EXISTS ragoff_companion_growth (
 profile_id INTEGER PRIMARY KEY, version INTEGER NOT NULL DEFAULT 1 CHECK(version=1),
 max_hp INTEGER NOT NULL CHECK(max_hp>0), max_sp INTEGER NOT NULL CHECK(max_sp>0)
);
CREATE TRIGGER IF NOT EXISTS ragoff_companion_growth_cleanup AFTER DELETE ON ragoff_companion
BEGIN DELETE FROM ragoff_companion_growth WHERE profile_id=OLD.id; END;
COMMIT;
