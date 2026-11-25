BEGIN IMMEDIATE;
CREATE TABLE ragoff_companion_build_next (
 profile_id INTEGER PRIMARY KEY REFERENCES ragoff_companion(id) ON DELETE CASCADE,
 build TEXT NOT NULL CHECK(build IN ('spear','falcon','battle','storm','vermilion','pillar','mobber'))
);
INSERT INTO ragoff_companion_build_next SELECT profile_id,build FROM ragoff_companion_build;
DROP TRIGGER IF EXISTS ragoff_companion_build_cleanup;
DROP TABLE ragoff_companion_build;
ALTER TABLE ragoff_companion_build_next RENAME TO ragoff_companion_build;
CREATE TRIGGER ragoff_companion_build_cleanup AFTER DELETE ON ragoff_companion
BEGIN DELETE FROM ragoff_companion_build WHERE profile_id=OLD.id; END;
COMMIT;
