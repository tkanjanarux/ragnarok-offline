"""Knight opens, bystanders survive splash and the team follows a walking owner."""
import struct
import time
from nearby_hunt_fixture import c, knight, mage, priest, ui, api, egg, hp, damage, wait, chat, position
from check_m4_exp import warp
from protocol import entry

ui('list',0)
api(c,f"skills {knight['id']} bowlingbash")
api(c,f"skills {mage['id']} firebolt")
target=egg(152,180)
assert hp(target)==60000
chat('hunt on')
# Acquire the shared focus first, then put the bystander directly beside it.
time.sleep(.45)
neighbor=egg(153,180,1078)
assert hp(neighbor)==60000
order=[]
def party_hit(i,b):
    skill,src,dst=damage(i,b)
    if src not in (knight['actor'],mage['actor']): return False
    assert dst==target,(src,dst,target,hp(target),hp(neighbor),position("StageOwner"))
    if src==mage['actor']: assert knight['actor'] in order,order
    order.append(src)
    return 62 in skills and mage['actor'] in order
skills=set()
def observe(i,b):
    skills.add(damage(i,b)[0])
    return party_hit(i,b)
wait(c,observe,25)
assert hp(neighbor)==60000
print('PASS Knight first, Mage follows, Bowling Bash adjacent bystander untouched')
chat('hunt off')
ui('list',0)
time.sleep(.8)
held=hp(target)
time.sleep(1.5)
assert hp(target)==held
ui('hunt on',1)
# Ordinary walking keeps hunt enabled. Cross the leash while the egg stays put.
ident, desc=entry('clif_parse_WalkToXY')
x,y=150,167
packet=bytearray(desc['length'])
struct.pack_into('<H',packet,0,ident)
at=desc['offsets'][0]
packet[at:at+3]=bytes((x>>2, ((x&3)<<6)|(y>>4), (y&15)<<4))
c.send(packet)
for _ in range(60):
    here=position('StageOwner')
    if here==(x,y) and all(max(abs(a-b) for a,b in zip(position(r['name']),here))<=4 for r in (knight,mage,priest)): break
    time.sleep(.2)
else: raise AssertionError(('regroup',here,[(r['name'],position(r['name'])) for r in (knight,mage,priest)]))
ui('list',1)
held=hp(target)
time.sleep(2)
assert hp(target)==held
print('PASS actual owner walk beyond 12 cells, hunt remains on, team regrouped and damage stopped')
warp(c,'prontera 150 180')
ui('list',0)
c.close()
