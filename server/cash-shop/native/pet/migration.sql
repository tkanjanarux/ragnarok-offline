-- Additive SQLite-only migration; run with writers stopped and a verified backup.
-- Never drop a nonempty journal or restore an old database after new writes.
CREATE TABLE IF NOT EXISTS ragoff_catalogue_pet_journal (
 owner_char INTEGER PRIMARY KEY,
 format INTEGER NOT NULL CHECK(format=1),
 item_size INTEGER NOT NULL CHECK(item_size>0),
 slots INTEGER NOT NULL CHECK(slots>0),
 before_hex TEXT NOT NULL,
 after_hex TEXT NOT NULL,
 pet_id INTEGER NOT NULL UNIQUE
);
