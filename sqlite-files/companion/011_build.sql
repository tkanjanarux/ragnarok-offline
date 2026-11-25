BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS ragoff_companion_build (
 profile_id INTEGER PRIMARY KEY REFERENCES ragoff_companion(id) ON DELETE CASCADE,
 build TEXT NOT NULL CHECK(build IN ('spear','falcon','battle','storm','vermilion','pillar'))
);
CREATE TRIGGER IF NOT EXISTS ragoff_companion_build_cleanup AFTER DELETE ON ragoff_companion
BEGIN DELETE FROM ragoff_companion_build WHERE profile_id=OLD.id; END;
COMMIT;
