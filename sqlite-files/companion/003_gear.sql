-- Explicit staging migration; Char inventory guard remains required while rows exist.
BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS ragoff_companion_gear (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 profile_id INTEGER NOT NULL,
 owner_account INTEGER NOT NULL,
 owner_char INTEGER NOT NULL,
 nameid INTEGER NOT NULL,
 unique_id TEXT NOT NULL UNIQUE,
 state INTEGER NOT NULL DEFAULT 0 CHECK(state IN (0,1)),
 equip INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ragoff_companion_gear_owner ON ragoff_companion_gear(owner_char);
CREATE TRIGGER IF NOT EXISTS ragoff_companion_gear_protect BEFORE DELETE ON ragoff_companion
WHEN EXISTS(SELECT 1 FROM ragoff_companion_gear WHERE profile_id=OLD.id)
BEGIN SELECT RAISE(ABORT,'Return companion equipment before releasing profile'); END;
COMMIT;
