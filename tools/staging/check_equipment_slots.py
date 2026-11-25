"""Fit ten actual equipment positions simultaneously, then change a two-slot piece."""
from pathlib import Path
import sqlite3,time
from check_m6_profiles import api
from check_m8_gear import held,returned,transfer,conserved
from protocol import login
root=Path('/stage')
assert (root/'STAGING_ONLY').exists()
db=sqlite3.connect(root/'ragoff-stage.sqlite3')
names=[1101,2101,2302,5354,5401,2265,2501,2401,2601,2601,5502]
uids=[644249399965000+i for i in range(len(names))]
db.executemany('insert into inventory(char_id,nameid,amount,identify,unique_id) values(150001,?,1,1,?)',zip(names,uids))
db.execute('UPDATE ragoff_companion SET hp=g.max_hp,sp=g.max_sp FROM ragoff_companion_growth g WHERE g.profile_id=ragoff_companion.id')
db.commit()
c=login()
c.command('@setbattleflag companion_enable 1')
c.command('@jobchange 7')
c.command('@set BaseLevel 85')
pid=next(r['id'] for r in api(c,'list')[0] if r['job']==7)
for i,uid in enumerate(uids):
    seq=99230+i
    c.command(f'@companion ui {seq} inspect {pid} ui2 skills7 gear3 syrup1 hunter1')
    slot=0
    while True:
        _,p=c.until({0x8e})
        t=p[4:].rstrip(b'\0').decode().split()
        if t[:2]!=['[RCO1]',str(seq)]:continue
        if t[2]=='bag' and t[5]==str(uid):slot=int(t[3])
        if t[2]=='end':break
    assert slot,names[i]
    transfer(c,pid,slot)
    conserved(uid)
gids={int(uid):g for g,uid,_,_ in held(pid)}
def masks():return {int(uid):m for g,uid,m,_ in held(pid)}
api(c,f'summon {pid}')
api(c,f'stop {pid}')
for uid in uids[:-1]:
    msg=api(c,f'equip {pid} {gids[uid]}')[1]
    assert 'equipped and saved' in msg,(uid,msg)
m=masks()
assert all(m[u]>0 for u in uids[:-1]) and len(set(m[u] for u in uids[:-1]))==10,m
api(c,f'bench {pid}')
api(c,f'summon {pid}')
assert masks()==m
api(c,f'stop {pid}')
assert 'equipped and saved' in api(c,f'equip {pid} {gids[uids[-1]]}')[1]
new=masks()
assert new[uids[3]]==new[uids[4]]==0 and new[uids[-1]]==m[uids[3]]|m[uids[4]]
api(c,f'bench {pid}')
for uid in uids:
    transfer(c,pid,gids[uid],False)
    returned(uid)
print('PASS ten occupied native positions incl two distinct accessories, resummon and two-slot hood replacement')
c.close()
