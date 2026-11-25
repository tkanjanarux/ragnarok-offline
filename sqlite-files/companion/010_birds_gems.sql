BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS ragoff_companion_rental (
 profile_id INTEGER PRIMARY KEY REFERENCES ragoff_companion(id) ON DELETE CASCADE,
 owner_char INTEGER NOT NULL
);
CREATE TRIGGER IF NOT EXISTS ragoff_companion_rental_cleanup AFTER DELETE ON ragoff_companion
BEGIN DELETE FROM ragoff_companion_rental WHERE profile_id=OLD.id; END;
COMMIT;
