"""Switch every profile in reserve without changing supply, item identity, or wallet."""
from nearby_hunt_fixture import c,knight,priest,mage,stage
from build_fixture import BuildFixture
from check_m8_gear import held,slot,transfer
import time,re
from check_m4_skills import wait

f=BuildFixture(c)
for p in (knight,priest,mage): f.note(f'bench {p["id"]}')
f.note('recruit hunter')
hunter=next(int(t[1]) for t in f.frames('list') if t[0]=='row' and t[2]=='11')
kid,pid,wid=knight['id'],priest['id'],mage['id']
c.command('@jobchange 3')
c.command('@set JobLevel 50')
c.command('@jobchange 11')
c.command('@set BaseLevel 83')
c.command('@set JobLevel 39')
c.command('@item 1157 1')
transfer(c,kid,slot(c,1157))
f.note(f'summon {kid}')
f.note(f'stop {kid}')
assert 'equipped and saved' in f.note(f'equip {kid} {held(kid)[-1][0]}')
assert 'Reserve' in f.note(f'build {kid} spear')
f.note(f'bench {kid}')
f.note(f'skills {kid} quicken')
f.select(kid,'sword')
assert 'skills=quicken' in f.note(f'config {kid}')
f.db.execute('insert into ragoff_companion_supply select id,owner_char,501,15 from ragoff_companion where id=?',(kid,))
def stable():
    cols=','.join(x[1] for x in f.db.execute('pragma table_info(ragoff_companion_gear)') if x[1]!='equip')
    return [f.db.execute('select '+cols+' from ragoff_companion_gear order by id').fetchall()]+[f.db.execute('select * from '+t+' order by rowid').fetchall() for t in ('ragoff_companion_gear_details','ragoff_companion_gear_options','ragoff_companion_supply','ragoff_companion_preset','ragoff_companion_rental')]

initial=stable()
for id_,key,skill in [(kid,'spear',57),(kid,'sword',60),(pid,'battle',65),(pid,'support',28),(hunter,'falcon',129),(hunter,'double',46),(wid,'storm',89),(wid,'vermilion',85),(wid,'pillar',80),(wid,'bolt',19)]:
    f.select(id_,key)
    print("JOB",key,{row[1]: row[4] for row in f.frames(f"inspect {id_}") if row[0]=="skill"},flush=True)
    assert stable()==initial
    assert f.ranks(id_)[skill]>0,(key,f.ranks(id_))
    assert 'Summoned' in f.note(f'summon {id_}')
    actor=int(f.row(id_)[11])
    c.command('@companion status')
    packet=wait(c,lambda i,b:i==0x8e and f'Companion id={actor} '.encode() in b)
    stats={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',packet.decode(errors='replace'))}
    print(key,[stats[k] for k in ('str','agi','vit','int','dex','luk')],f.ranks(id_),flush=True)
    assert 'reserve' in f.note(f'bench {id_}').lower()
assert f.db.execute('select equip from ragoff_companion_gear where nameid=1157').fetchone()==(0,)
assert 'Unknown' in f.note(f'build {pid} spear')
print('PASS ten builds, real shell stats, equipped sword stored, inventory properties, supplies and original custom policy preserved')
c.close()
