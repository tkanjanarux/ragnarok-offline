"""Hunter with an Archer owner. Check the first shot and switching arrow elements."""
import re
import struct
import sqlite3
import time
from nearby_hunt_fixture import c, knight, mage, priest, api, egg, hp, damage, position, stage, wait
from companion_ai_fixture import attack
from check_m4_exp import warp
from protocol import entry

for row in (knight,mage,priest):
    api(c,f"bench {row['id']}")
c.command('@jobchange 3')
c.command('@set BaseLevel 80')
c.command('@set JobLevel 40')
c.command('@allskill')
fixture=stage/'npc/custom/qa_hunter_bow.txt'
fixture.write_text('-\tscript\tQA Hunter Bow\t-1,{\nOnInit: bindatcmd "testhunterbow",strnpcinfo(3)+"::OnBow",99,99; end;\nOnBow: getitem 1701,1; equip 1701; getitem 1750,100; equip 1750; end;\n}\n')
c.command('@loadnpc npc/custom/qa_hunter_bow.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
c.command('@testhunterbow')
assert 'Recruited' in api(c,'recruit hunter')[1]
db=sqlite3.connect(stage/'ragoff-stage.sqlite3',isolation_level=None)
pid,owner=db.execute('select id,owner_char from ragoff_companion where job=11').fetchone()
for item in (1752,1754):
    db.execute('insert into ragoff_companion_supply values (?,?,?,20)',(pid,owner,item))
api(c,f'summon {pid}')
c.command('@companion ui 800 list ui2 hunter1 hunt1')
b=wait(c,lambda i,b:i==0x8e and f'[RCO1] 800 row {pid} 3 '.encode() in b)
actor=int(b[4:].split()[13])
api(c,f'skills {pid} none')
api(c,f'assist {pid}')
def arrows():
    return dict(db.execute('select nameid,amount from ragoff_companion_supply where profile_id=?',(pid,)))
def exercise(species,preferred,spare):
    target=egg(162,180,species)
    neighbor=egg(163,180,1002)
    before=arrows()
    time.sleep(.8)
    assert hp(target)==60000 and arrows()==before
    attack(c,target)
    wait(c,lambda i,b:damage(i,b)[1:]==(2000001,target),10)
    wait(c,lambda i,b:damage(i,b)[1:]==(actor,target),16)
    api(c,f'stop {pid}')
    assert hp(neighbor)==60000
    after=arrows()
    assert after[preferred]<before[preferred] and after[spare]==before[spare],(before,after)
    c.command('@killmonster2')
    warp(c,'prontera 150 180')
    api(c,f'assist {pid}')
exercise(1010,1752,1754) # Willow, Earth
exercise(1119,1754,1752) # Peco Peco, Fire
print('PASS Archer career assists only after engagement and switches to Fire/Crystal for Earth/Fire targets')
api(c,f'stop {pid}')
budgets={int(level):int(points) for level,points in re.findall(r'Level: (\d+)\s+Points: (\d+)',(stage/'db/re/statpoint.yml').read_text())}
def expected(base):
    v={'dex':1,'agi':1,'vit':1}
    left=budgets[base]
    for stat,goal in [('dex',40),('vit',15),('agi',30),('dex',65),('agi',50),('vit',25),('dex',90),('agi',75),('dex',99),('vit',40),('agi',99)]:
        while v[stat]<goal:
            cost=2+(v[stat]-1)//10
            if cost>left:return v,left
            left-=cost
            v[stat]+=1
    return v,left
for job,base in [(3,10),(3,52),(11,52),(11,81),(11,99),(3,30)]:
    c.command(f'@jobchange {job}')
    c.command(f'@set BaseLevel {base}')
    time.sleep(.8)
    c.command('@companion status')
    packet=wait(c,lambda i,b:i==0x8e and f'Companion id={actor} '.encode() in b)
    stats={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',packet.decode(errors='replace'))}
    values,left=expected(base)
    assert stats['class']==job and stats['points']==left and all(stats[k]==v for k,v in values.items()),stats
print('PASS native stat budget and DEX/VIT/AGI steps across level changes and promotion')
api(c,f'bench {pid}')
db.execute('delete from ragoff_companion_supply where profile_id=?',(pid,))
api(c,f'summon {pid}')
api(c,f'assist {pid}')
name=db.execute('select name from ragoff_companion where id=?',(pid,)).fetchone()[0]
code,desc=entry('clif_parse_WalkToXY')
msg=bytearray(desc['length'])
struct.pack_into('<H',msg,0,code)
x,y=150,190
off=desc['offsets'][0]
msg[off:off+3]=bytes((x>>2,((x&3)<<6)|(y>>4),(y&15)<<4))
c.send(msg)
for _ in range(80):
    if position('StageOwner')==(x,y) and max(abs(a-b) for a,b in zip(position(name),(x,y)))<=4:break
    time.sleep(.1)
else:raise AssertionError('empty-quiver Hunter failed to follow owner')
print('PASS empty-quiver companion follows owner on foot')
c.close()
