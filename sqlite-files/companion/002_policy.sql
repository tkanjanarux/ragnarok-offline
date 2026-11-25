-- Additive companion settings. M6 ignores this table when rolled back.
BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS ragoff_companion_policy (
 profile_id INTEGER PRIMARY KEY,
 role TEXT NOT NULL CHECK(role IN ('tank','support','dps')),
 skill_order TEXT NOT NULL
);
CREATE TRIGGER IF NOT EXISTS ragoff_companion_policy_cleanup AFTER DELETE ON ragoff_companion
BEGIN DELETE FROM ragoff_companion_policy WHERE profile_id=OLD.id; END;
COMMIT;
