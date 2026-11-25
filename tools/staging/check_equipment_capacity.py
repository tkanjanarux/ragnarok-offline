"""A full reserve of heavy spares must not prevent a summon or equip."""
from pathlib import Path
import sqlite3
from check_m6_profiles import api
from check_m8_gear import transfer,slot,held,conserved
from protocol import login
root=Path('/stage')
assert (root/'STAGING_ONLY').exists()
db=sqlite3.connect(root/'ragoff-stage.sqlite3')
db.execute('UPDATE ragoff_companion SET hp=g.max_hp,sp=g.max_sp FROM ragoff_companion_growth g WHERE g.profile_id=ragoff_companion.id')
db.commit()
c=login()
c.command('@setbattleflag companion_enable 1')
c.command('@jobchange 7')
c.command('@set BaseLevel 90')
pid=next(r['id'] for r in api(c,'list')[0] if r['job']==7)
for n in range(25):
    c.command('@item 1370 1')
    selection=slot(c,1370)
    transfer(c,pid,selection,success=n<24)
items=held(pid)
assert len(items)==24 and len({u for _,u,_,_ in items})==24
assert db.execute('select sum(amount) from inventory where nameid=1370 and char_id=150001').fetchone()==(1,)
assert 'Summoned' in api(c,f'summon {pid}')[1]
api(c,f'stop {pid}')
for gid,uid,_,_ in items[:3]:
    assert 'equipped and saved' in api(c,f'equip {pid} {gid}')[1]
    assert sum(bool(mask) for _,_,mask,_ in held(pid))==1
api(c,f'bench {pid}')
assert 'Summoned' in api(c,f'summon {pid}')[1]
for _,uid,_,_ in items:conserved(int(uid))
print('PASS 24 Doom Slayers held, 25th retained in player bag, spare weight does not block summon or swap')
c.close()
