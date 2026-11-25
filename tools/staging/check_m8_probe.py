"""Small gear path probe on an explicitly disposable fresh fixture."""
import pathlib,sys,time,re,sqlite3
sys.path.insert(0,'/tests')
from protocol import login
from check_m6_profiles import api
from check_m4_skills import wait
assert pathlib.Path('/stage/M8_TEST').exists()
c=login();c.command('@setbattleflag companion_enable 1');c.command('@heal')
rows,_,_=api(c,'recruit knight');kid=rows[0]['id']
c.command('@item 1101 1');c.command('@companion inventory')
b=wait(c,lambda i,b:i==0x8e and b'Inventory slot ' in b and b'(1101)' in b)
slot=int(re.search(rb'slot (\d+)',b)[1]);print('SLOT',slot,flush=True)
api(c,f'give {kid} {slot}')
print(wait(c,lambda i,b:i==0x8e and (b'Equipment given.' in b or b'failed' in b or b'cancelled' in b))[4:].decode(),flush=True)
db=sqlite3.connect('file:/stage/ragoff-stage.sqlite3?mode=ro',uri=True);gid=db.execute('SELECT id FROM ragoff_companion_gear WHERE profile_id=?',(kid,)).fetchone()[0];db.close()
rows,n,_=api(c,f'summon {kid}');print(n,rows,flush=True)
api(c,f'stop {kid}')
print(api(c,f'equip {kid} {gid}')[1],flush=True)
api(c,f'bench {kid}');print('BENCH',flush=True)
print(api(c,f'summon {kid}')[1],flush=True)
api(c,f'bench {kid}');api(c,f'take {kid} {gid}')
print(wait(c,lambda i,b:i==0x8e and (b'Equipment returned' in b or b'failed' in b))[4:].decode(),flush=True)
c.close();print('GEAR_PROBE_PASS',flush=True)
