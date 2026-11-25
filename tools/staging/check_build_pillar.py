"""Exercise each native ground spell, including new bystanders during its lifetime."""
import re,struct,time
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
# An approaching monster moves toward the owner along a real walk path.
f.select(wid,'pillar')
f.note(f'summon {wid}')
actor=int(f.row(wid)[11])
f.note(f'assist {wid}')
path=stage/'npc/custom/qa_pillar.txt'
path.write_text('''-	script	QA Pillar	-1,{
OnInit:
 bindatcmd "qapillar",strnpcinfo(3)+"::OnRun",99,99; end;
OnRun:
 .@id=atoi(.@atcmd_parameters$[0]); .@target=atoi(.@atcmd_parameters$[1]);
 setunitdata .@id,UMOB_MODE,MD_AGGRESSIVE|MD_CANMOVE|MD_CANATTACK|MD_KNOCKBACKIMMUNE;
 setunitdata .@id,UMOB_SPEED,500;
 unitattack .@id,.@target;
 end;
}
''')
c.command('@loadnpc npc/custom/qa_pillar.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
f.note(f'preset {wid} protect')
# Fire Pillar is reserved for defense. Isolate the trap from bolt damage.
f.note(f'skills {wid} pillar')
# A nearby idle monster blocks placement, even though the pursuing mob is eligible.
bystander = egg(153,181)
pursuer = egg(157,180,1007)
log = stage / 'artifacts/map-server.log'
offset = log.stat().st_size
c.command(f'@qapillar {pursuer} 2000001')
time.sleep(4)
assert hp(bystander) == 60000
positions = re.findall(rb'skill=80 .*?position=(\d+),(\d+)', log.read_bytes()[offset:])
assert all(max(abs(int(x)-153), abs(int(y)-181)) > 3 for x,y in positions), positions
c.command('@killmonster2')
print('PASS Fire Pillar keeps its footprint clear of the idle monster', flush=True)
for attempt in range(4):
    target=egg(157,180,1007)
    c.command(f'@qapillar {target} 2000001')
    try:
        hit(80,actor,target,10)
        break
    except AssertionError:
        c.command('@killmonster2')
else: raise AssertionError('no native Fire Pillar hit on pursuing monster')
print('PASS Fire Pillar intercepted attacker on approach',flush=True)
c.close()
