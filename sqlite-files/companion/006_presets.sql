BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS ragoff_companion_preset (
 profile_id INTEGER PRIMARY KEY,
 preset TEXT NOT NULL CHECK(preset IN ('custom','protect','assist','conserve'))
);
CREATE TRIGGER IF NOT EXISTS ragoff_companion_preset_cleanup AFTER DELETE ON ragoff_companion
BEGIN DELETE FROM ragoff_companion_preset WHERE profile_id=OLD.id; END;
COMMIT;
