"""Buy a single Blue Potion stack in a disposable field and reconcile the receipt."""
import pathlib
import sqlite3
import struct
import time

from protocol import TABLE, entry, login

assert pathlib.Path('/stage/STAGING_ONLY').is_file()
for packet_id, length in [(0x8ca, -1), (0xb6e, 14), (0x849, 16)]:
    TABLE[str(packet_id)] = {'length': length}
db = sqlite3.connect('file:/stage/ragoff-stage.sqlite3?mode=ro', uri=True)
def quantity():
    return db.execute('select coalesce(sum(amount),0) from inventory where char_id=150001 and nameid=505').fetchone()[0]

client = login()
client.command('@cash 10000')
time.sleep(.5)

def balance(tab):
    client.send(struct.pack('<HI', 0xb6d, tab))
    cash, free, echoed = struct.unpack_from('<III', client.until({0xb6e})[1], 2)
    assert echoed == tab
    return cash, free

starting = balance(6)
before = quantity()
cash_log_start = db.execute('select coalesce(max(id),0) from cashlog').fetchone()[0]
pick_log_start = db.execute('select coalesce(max(id),0) from picklog').fetchone()[0]
buy = struct.pack('<HHHIIIH', 0x848, 20, 1, 0, 505, 15, 6)
client.command('@warp mjolnir_12')
client.until({0x91})
client.send(buy)
receipt = struct.unpack_from('<IHII', client.until({0x849})[1], 2)
assert receipt[1:] == (6, *starting), receipt
client.send(struct.pack('<H', entry('clif_parse_LoadEndAck')[0]))
time.sleep(.4)
assert balance(6) == starting
client.send(buy)
receipt = struct.unpack_from('<IHII', client.until({0x849})[1], 2)
assert receipt == (505, 0, starting[0]-75, starting[1]), receipt
assert balance(0) == receipt[2:]
assert balance(0) == receipt[2:]
client.close()
for _ in range(50):
    if quantity() == before+15:
        break
    time.sleep(.2)
assert quantity() == before+15
assert db.execute("select amount,map from cashlog where id>? and char_id=150001 and type='$'",
                  (cash_log_start,)).fetchall() == [(-75, 'mjolnir_12')]
assert db.execute("select nameid,amount,map from picklog where id>? and char_id=150001 and type='$'",
                  (pick_log_start,)).fetchall() == [(505, 15, 'mjolnir_12')]
print(f'Field purchase passed. Map-load rejection 6, debit 75, saved inventory {before} -> {quantity()}, repeated balance checks preserve funds.')
