"""Verify Hunter as a backline guard target and native Priest support recipient."""
import sqlite3
import struct
from companion_ai_fixture import setup, api, wait, stage, spawn
from check_ai_guard import target_mob_command

c,rows=setup(7,8)
target_mob_command(c)
knight,priest=rows[7],rows[8]
assert 'Recruited' in api(c,'recruit hunter')[1]
with sqlite3.connect(stage/'ragoff-stage.sqlite3') as db:
    pid,name=db.execute('select id,name from ragoff_companion where job=11').fetchone()
assert 'Summoned' in api(c,f'summon {pid}')[1]
c.command('@companion ui 777 list ui2 hunter1 hunt1')
b=wait(c,lambda i,b:i==0x8e and f'[RCO1] 777 row {pid} '.encode() in b)
actor=int(b[4:].split()[13])
def spell(skill,caster,recipient):
    wait(c,lambda i,b:i==0x9cb and struct.unpack_from('<H',b,2)[0]==skill and struct.unpack_from('<II',b,8)==(recipient,caster),12)
api(c,f'assist {pid}')
api(c,f'stop {pid}')
api(c,f"skills {priest['id']} heal,blessing")
c.command(f'#set {name} Hp 20')
c.command(f"@companion ui 991 assist {priest['id']}")
spell(28,priest['actor'],actor)
spell(34,priest['actor'],actor)
api(c,f"stop {priest['id']}")
api(c,f"preset {knight['id']} protect")
api(c,f"skills {knight['id']} provoke")
mob,_,_=spawn(c,1002)
c.command(f'@aiguard {mob} {actor} {name}')
wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(mob,actor))
c.command(f"@companion ui 992 assist {knight['id']}")
spell(6,knight['actor'],mob)
wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(mob,knight['actor']))
print('PASS Priest heals and blesses Hunter; Knight provokes and takes the next hit')
c.close()
