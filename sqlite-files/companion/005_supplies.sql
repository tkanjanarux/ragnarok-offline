BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS ragoff_companion_supply (
 profile_id INTEGER NOT NULL, owner_char INTEGER NOT NULL, nameid INTEGER NOT NULL,
 amount INTEGER NOT NULL CHECK(amount BETWEEN 0 AND 1000),
 PRIMARY KEY(profile_id,nameid)
);
CREATE TABLE IF NOT EXISTS ragoff_companion_supply_journal (
 owner_char INTEGER NOT NULL, nameid INTEGER NOT NULL,
 before_amount INTEGER NOT NULL, delta INTEGER NOT NULL,
 PRIMARY KEY(owner_char,nameid)
);
CREATE TRIGGER IF NOT EXISTS ragoff_companion_supply_protect BEFORE DELETE ON ragoff_companion
WHEN EXISTS(SELECT 1 FROM ragoff_companion_supply WHERE profile_id=OLD.id AND amount>0)
BEGIN SELECT RAISE(ABORT,'Return companion supplies before releasing profile'); END;
CREATE TRIGGER IF NOT EXISTS ragoff_companion_supply_cleanup AFTER DELETE ON ragoff_companion
BEGIN DELETE FROM ragoff_companion_supply WHERE profile_id=OLD.id; END;
COMMIT;
