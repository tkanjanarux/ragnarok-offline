"""Disabled bag rows and give refusals use the same reason, across a full transfer batch."""
import sqlite3,time
from pathlib import Path
from check_m6_profiles import api
from check_m8_gear import transfer,returned,conserved,held
from protocol import login
root=Path('/stage')
assert (root/'STAGING_ONLY').exists()
db=sqlite3.connect(root/'ragoff-stage.sqlite3')
start=644249399970000
items=[(5354,'expire_time',1900000000,'Rental item'),(5355,'bound',1,'Bound item'),
       (5354,'favorite',1,'Remove from favorites first'),(5355,'identify',0,'Identify or repair'),
       (1157,None,0,'Companion job requirement'),(5401,None,0,'Companion level requirement')]
for n,(name,col,value,_) in enumerate(items):
    db.execute('insert into inventory(char_id,nameid,amount,identify,unique_id) values(150001,?,1,1,?)',(name,start+n))
    if col:db.execute(f'update inventory set {col}=? where unique_id=?',(value,start+n))
uid=start+100
db.execute('insert into inventory(char_id,nameid,amount,identify,unique_id,refine,option_id0,option_val0) values(150001,5354,1,1,?,4,1,81)',(uid,))
db.commit()
c=login()
c.command('@setbattleflag companion_enable 1')
c.command('@jobchange 7')
c.command('@set BaseLevel 55')
pid=next(r['id'] for r in api(c,'list')[0] if r['job']==9)
def bag(seq):
    c.command(f'@companion ui {seq} inspect {pid} ui2 skills7 gear3 syrup1 hunter1')
    out={}
    while True:
        _,msg=c.until({0x8e})
        t=msg[4:].rstrip(b'\0').decode().split()
        if t[:2]!=['[RCO1]',str(seq)]:continue
        if t[2] in ('blocked','bag'):out[int(t[5])]=t[2:]
        if t[2]=='end':return out
rows=bag(701)
for i,(_,_,_,reason) in enumerate(items):
    blocked=rows[start+i]
    assert blocked[0]=='blocked' and ' '.join(blocked[4:]).startswith(reason),blocked
    assert api(c,f'give {pid} {blocked[1]}')[1].startswith(reason)
    conserved(start+i)
for i in range(100):
    row=bag(702+i)[uid]
    assert row[0]=='bag'
    transfer(c,pid,int(row[1]))
    conserved(uid)
    gid=next(g[0] for g in held(pid) if int(g[1])==uid)
    transfer(c,pid,gid,False)
    returned(uid)
    assert db.execute('select amount,refine,option_id0,option_val0 from inventory where unique_id=?',(uid,)).fetchall()==[(1,4,1,81)]
print('PASS six blocked reasons match enforced give checks; 100 exact modified-item round trips')
c.close()
