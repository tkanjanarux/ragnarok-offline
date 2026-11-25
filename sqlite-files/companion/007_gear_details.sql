BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS ragoff_companion_gear_details (
 gear_id INTEGER PRIMARY KEY,
 refine INTEGER NOT NULL CHECK(refine BETWEEN 0 AND 20),
 card0 INTEGER NOT NULL, card1 INTEGER NOT NULL, card2 INTEGER NOT NULL, card3 INTEGER NOT NULL
);
CREATE TRIGGER IF NOT EXISTS ragoff_companion_gear_details_cleanup AFTER DELETE ON ragoff_companion_gear
BEGIN DELETE FROM ragoff_companion_gear_details WHERE gear_id=OLD.id; END;
-- Even an older binary must not reconstruct a detailed item as plain.
CREATE TRIGGER IF NOT EXISTS ragoff_companion_gear_return_details BEFORE INSERT ON inventory
WHEN EXISTS (SELECT 1 FROM ragoff_companion_gear g JOIN ragoff_companion_gear_details d ON d.gear_id=g.id
 WHERE g.unique_id=CAST(NEW.unique_id AS TEXT) AND
 (d.refine<>NEW.refine OR d.card0<>NEW.card0 OR d.card1<>NEW.card1 OR d.card2<>NEW.card2 OR d.card3<>NEW.card3))
BEGIN SELECT RAISE(ABORT,'Companion equipment metadata mismatch'); END;
CREATE TRIGGER IF NOT EXISTS ragoff_companion_gear_ack_details BEFORE DELETE ON ragoff_companion_gear
WHEN OLD.state=1 AND EXISTS (SELECT 1 FROM ragoff_companion_gear_details d WHERE d.gear_id=OLD.id
 AND NOT EXISTS (SELECT 1 FROM inventory i WHERE i.char_id=OLD.owner_char AND i.unique_id=CAST(OLD.unique_id AS INTEGER)
 AND i.nameid=OLD.nameid AND i.amount=1 AND i.refine=d.refine AND i.card0=d.card0 AND i.card1=d.card1
 AND i.card2=d.card2 AND i.card3=d.card3))
BEGIN SELECT RAISE(ABORT,'Returned companion item missing or changed'); END;
COMMIT;
