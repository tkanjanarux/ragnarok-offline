BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS ragoff_companion_gear_options (
 gear_id INTEGER PRIMARY KEY,
 enchantgrade INTEGER NOT NULL DEFAULT 0,
 option_id0 INTEGER NOT NULL DEFAULT 0,
 option_val0 INTEGER NOT NULL DEFAULT 0,
 option_parm0 INTEGER NOT NULL DEFAULT 0,
 option_id1 INTEGER NOT NULL DEFAULT 0,
 option_val1 INTEGER NOT NULL DEFAULT 0,
 option_parm1 INTEGER NOT NULL DEFAULT 0,
 option_id2 INTEGER NOT NULL DEFAULT 0,
 option_val2 INTEGER NOT NULL DEFAULT 0,
 option_parm2 INTEGER NOT NULL DEFAULT 0,
 option_id3 INTEGER NOT NULL DEFAULT 0,
 option_val3 INTEGER NOT NULL DEFAULT 0,
 option_parm3 INTEGER NOT NULL DEFAULT 0,
 option_id4 INTEGER NOT NULL DEFAULT 0,
 option_val4 INTEGER NOT NULL DEFAULT 0,
 option_parm4 INTEGER NOT NULL DEFAULT 0
);
CREATE TRIGGER IF NOT EXISTS ragoff_companion_options_cleanup AFTER DELETE ON ragoff_companion_gear
BEGIN DELETE FROM ragoff_companion_gear_options WHERE gear_id=OLD.id; END;
CREATE TRIGGER IF NOT EXISTS ragoff_companion_options_return BEFORE INSERT ON inventory
WHEN EXISTS (SELECT 1 FROM ragoff_companion_gear g JOIN ragoff_companion_gear_options o ON o.gear_id=g.id
 WHERE g.unique_id=CAST(NEW.unique_id AS TEXT) AND (o.enchantgrade<>NEW.enchantgrade OR o.option_id0<>NEW.option_id0 OR o.option_val0<>NEW.option_val0 OR o.option_parm0<>NEW.option_parm0 OR o.option_id1<>NEW.option_id1 OR o.option_val1<>NEW.option_val1 OR o.option_parm1<>NEW.option_parm1 OR o.option_id2<>NEW.option_id2 OR o.option_val2<>NEW.option_val2 OR o.option_parm2<>NEW.option_parm2 OR o.option_id3<>NEW.option_id3 OR o.option_val3<>NEW.option_val3 OR o.option_parm3<>NEW.option_parm3 OR o.option_id4<>NEW.option_id4 OR o.option_val4<>NEW.option_val4 OR o.option_parm4<>NEW.option_parm4))
BEGIN SELECT RAISE(ABORT,'Companion option mismatch'); END;
CREATE TRIGGER IF NOT EXISTS ragoff_companion_options_ack BEFORE DELETE ON ragoff_companion_gear
WHEN OLD.state=1 AND EXISTS (SELECT 1 FROM ragoff_companion_gear_options o WHERE o.gear_id=OLD.id AND NOT EXISTS
 (SELECT 1 FROM inventory i WHERE i.char_id=OLD.owner_char AND i.unique_id=CAST(OLD.unique_id AS INTEGER) AND o.enchantgrade=i.enchantgrade AND o.option_id0=i.option_id0 AND o.option_val0=i.option_val0 AND o.option_parm0=i.option_parm0 AND o.option_id1=i.option_id1 AND o.option_val1=i.option_val1 AND o.option_parm1=i.option_parm1 AND o.option_id2=i.option_id2 AND o.option_val2=i.option_val2 AND o.option_parm2=i.option_parm2 AND o.option_id3=i.option_id3 AND o.option_val3=i.option_val3 AND o.option_parm3=i.option_parm3 AND o.option_id4=i.option_id4 AND o.option_val4=i.option_val4 AND o.option_parm4=i.option_parm4))
BEGIN SELECT RAISE(ABORT,'Returned companion options missing'); END;
COMMIT;
