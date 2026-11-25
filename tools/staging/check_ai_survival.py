import re
import struct
import time
from companion_ai_fixture import setup, api, wait, spawn, attack, owner
from check_ai_guard import target_mob_command
from check_m4_exp import warp

c,rows=setup(7)
tank,priest=rows[7],rows[8]
target_mob_command(c)
tid,pid=tank['id'],priest['id']
api(c,f'skills {tid} bash')
api(c,f'assist {tid}')
egg,x,y=spawn(c,1097)
c.command(f'@aiguard {egg} 0')
warp(c,f'prontera {x} {y}')
attack(c,egg)
def tank_hit(i,b):
    return ((i==0x8c8 and struct.unpack_from('<II',b,2)==(tank['actor'],egg)) or
            (i==0x1de and struct.unpack_from('<HII',b,2)==(5,tank['actor'],egg)))
wait(c,tank_hit)

def position(name):
    c.command('@where '+name)
    packet=wait(c,lambda i,b: i==0x8e and name.encode()+b' prontera ' in b)
    return tuple(map(int,re.search(rb'prontera (\d+) (\d+)',packet).groups()))

# Owner steps away while the knight still has a live, engaged melee target.
warp(c,f'prontera {x+6} {y}')
ox,oy=position('StageOwner')
def distance():
    px,py=position(tank['name'])
    return max(abs(px-ox),abs(py-oy))
assert distance()>2
c.command(f"#set {tank['name']} Hp {tank['max_hp']//8}")
end=time.monotonic()+7
while distance()>2:
    assert time.monotonic()<end, ('did not reach cover',position(tank['name']),(ox,oy),api(c,'list')[0])
    time.sleep(.2)
c.command(f"#set {tank['name']} Hp {tank['max_hp']*3//10}")
attack(c,egg)
c.s.settimeout(.2)
try: wait(c,tank_hit,2)
except AssertionError: pass
else: raise AssertionError('tank attacked before recovery')
assert distance()<=2
c.command(f"#heal {tank['name']}")
warp(c,f'prontera {x} {y}')
attack(c,egg)
wait(c,tank_hit)
print('PASS retreat, remain at cover at 30%, resume after recovery')
api(c,f'stop {tid}')
c.command('@killmonster2')
warp(c,'prontera 150 180')
assert 'Summoned' in api(c,f'summon {pid}')[1]
priest=next(r for r in api(c,'list')[0] if r['id']==pid)
api(c,f'preset {pid} custom')
api(c,f'skills {pid} blessing,heal')
c.command(f"#set {priest['name']} Sp {priest['max_sp']//5}")
c.command('@heal')
c.command(f'@companion ui 901 assist {pid}')
def skill(i,b,sk):
    return i==0x9cb and struct.unpack_from('<H',b,2)[0]==sk and struct.unpack_from('<I',b,12)[0]==priest['actor']
try: wait(c,lambda i,b:skill(i,b,34),2)
except AssertionError: pass
else: raise AssertionError('spent low SP on buff')
c.command('@set Hp 1')
wait(c,lambda i,b:skill(i,b,28) and struct.unpack_from('<I',b,8)[0]==owner)
c.command(f"#heal {priest['name']}")
wait(c,lambda i,b:skill(i,b,34))
print('PASS low SP withheld buff, healed owner, buff resumed at high SP')
c.close()
