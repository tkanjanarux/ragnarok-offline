"""Exercise each native ground spell, including new bystanders during its lifetime."""
import struct,time
from nearby_hunt_fixture import c,knight,priest,mage,egg,hp,stage,chat,query,damage
from build_fixture import BuildFixture
from check_m4_skills import wait
from check_m4_exp import warp
f=BuildFixture(c)
for profile in (knight,priest,mage): f.note(f'bench {profile["id"]}')
wid=mage['id']
c.command('@jobchange 11')
c.command('@set BaseLevel 83')
c.command('@set JobLevel 39')
c.command('@heal')
def hit(skill,actor,mob,n=25):
    return wait(c,lambda i,b:i==0x1de and damage(i,b)[0]==skill and damage(i,b)[2]==mob and struct.unpack_from('<i',b,24)[0]>0,n)
for key,skill in [('storm',89),('vermilion',85)]:
    f.select(wid,key)
    f.note(f'summon {wid}')
    actor=int(f.row(wid)[11])
    target=egg(155,180)
    other=egg(156,180)
    chat('hunt on')
    # While the neighbor is idle use safe single-target fallback.
    wait(c,lambda i,b:damage(i,b)[1:]==(actor,target) and damage(i,b)[0] in (14,19,20),20)
    assert hp(other)==60000
    c.command(f'@huntremove {other}')
    hit(skill,actor,target)
    late=egg(156,181)
    time.sleep(2)
    assert hp(late)==60000
    f.note(f'stop {wid}')
    c.command('@killmonster2')
    f.note(f'bench {wid}')
    print('PASS',key,'native hit, fallback, bystander enters during ground effect',flush=True)
c.close()
