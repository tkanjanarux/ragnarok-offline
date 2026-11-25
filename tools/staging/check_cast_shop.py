"""Verify the Permanent catalog, debit, receipt and saved equipment after field purchases."""
import sqlite3, struct, time
from pathlib import Path
from protocol import TABLE,login
from check_m4_exp import warp
from check_m4_skills import wait

stage=Path('/stage')
assert (stage/'STAGING_ONLY').exists()
for code,size in [(0x8ca,-1),(0xb6e,14),(0x849,16)]: TABLE[str(code)]={'length':size}
db=sqlite3.connect(stage/'ragoff-stage.sqlite3')
def items():
    return dict(db.execute('SELECT nameid,sum(amount) FROM inventory WHERE char_id=150001 GROUP BY nameid'))
hats={5354:250,5355:250,5286:400,5502:600}
before=items()
cashlog=db.execute('select coalesce(max(id),0) from cashlog').fetchone()[0]
c=login()
c.command('@cash 5000')
warp(c,'mjolnir_12 60 60')
c.send(struct.pack('<H',0x8c9))
p=wait(c,lambda i,b:i==0x8ca and struct.unpack_from('<H',b,6)[0]==4)
assert dict(struct.iter_unpack('<II',p[8:]))==hats
def balance():
    c.send(struct.pack('<HI',0xb6d,4))
    return struct.unpack_from('<III',c.until({0xb6e})[1],2)
start,free,tab=balance()
remaining=start
for item,price in hats.items():
    c.send(struct.pack('<HHHIIIH',0x848,20,1,0,item,1,4))
    p=wait(c,lambda i,b:i==0x849,5)
    remaining-=price
    assert struct.unpack_from('<IHII',p,2)==(item,0,remaining,free)
    assert balance()==(remaining,free,4)
c.close()
for _ in range(50):
    saved=items()
    if all(saved.get(i,0)==before.get(i,0)+1 for i in hats):break
    time.sleep(.2)
else:raise AssertionError(saved)
assert db.execute("select amount from cashlog where id>? and char_id=150001 and type='$' order by id",(cashlog,)).fetchall()==[(-p,) for p in hats.values()]
c=login()
assert balance()==(remaining,free,4)
print('PASS 4 field receipts, saved hats +1 each, four matching debits, reconnect balance',start,remaining)
c.close()
