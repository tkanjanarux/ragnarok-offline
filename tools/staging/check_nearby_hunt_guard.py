"""Tank guards the backline during an owner redirect, then rejoins the shared target."""
import struct
from nearby_hunt_fixture import c, knight, mage, owner, api, egg, ui, see_hit, spawn, wait, damage
from check_ai_guard import target_mob_command
from protocol import entry

action,_=entry('clif_parse_ActionRequest')
api(c,f"skills {knight['id']} none")
target_mob_command(c)
old=egg(152,180)
ui('hunt on',1)
see_hit(knight['actor'],old)
api(c,f"preset {knight['id']} protect")
api(c,f"skills {knight['id']} provoke")
stray,_,_=spawn(c,1002)
new=egg(151,179)
c.command(f"@aiguard {stray} {mage['actor']} {mage['name']}")
c.send(struct.pack('<HIB',action,new,0))
events=[]
def guard_and_return(i,b):
    code,src,dst=damage(i,b)
    if i==0x9cb:
        code=struct.unpack_from('<H',b,2)[0]
        dst,src=struct.unpack_from('<II',b,8)
    if src in (knight['actor'],owner,stray,mage['actor']):
        events.append((code,src,dst))
    guarded=any(a==knight['actor'] and t==stray for _,a,t in events)
    redirected=any(a==owner and t==new for _,a,t in events)
    return guarded and redirected
try: wait(c,guard_and_return,25)
except AssertionError as exc: raise AssertionError((stray,new,events[-40:])) from exc
c.command(f'@huntremove {stray}')
see_hit(knight['actor'],new)
print('PASS Knight defended Mage and rejoined the owner target after threat cleared')
c.command('@companion stop')
ui('list',0)
c.close()
