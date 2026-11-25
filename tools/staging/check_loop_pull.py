"""Exercise a real train, stop at a foreign player, then finish the same lap."""
import re
import time
from build_fixture import BuildFixture
from nearby_hunt_fixture import c,knight,priest,mage,stage,query,position,wait
from check_m4_exp import warp
from protocol import login
assert (stage/'STAGING_ONLY').is_file()
f=BuildFixture(c)
c.command("@set BaseLevel 88")
c.command("@set JobLevel 47")
c.command("@heal")
f.note(f'bench {mage["id"]}')
f.select(mage['id'],'storm')
f.note(f'summon {mage["id"]}')
for member in (knight,priest,mage):f.note(f'assist {member["id"]}')
f.note(f'skills {knight["id"]} provoke,endure')
peer=login('/stage/peer-fixture.json')
warp(peer,'prontera 179 171')
assert position('StagePeer')==(179,171)
npc=stage/'npc/custom/qa_loop.txt'
npc.write_text('''-	script	QA Loop	-1,{
OnInit:bindatcmd "loopmob",strnpcinfo(3)+"::OnRun",99,99;end;
OnRun:
 .@x=atoi(.@atcmd_parameters$[0]); .@y=atoi(.@atcmd_parameters$[1]);
 .@kind=atoi(.@atcmd_parameters$[2]);if(!.@kind).@kind=1369;
 monster "prontera",.@x,.@y,"Loop QA",.@kind,1; .@id=$@mobid[0];
 unitwarp .@id,"prontera",.@x,.@y;
 setunitdata .@id,UMOB_ATKMIN,1; setunitdata .@id,UMOB_ATKMAX,1;
 setunitdata .@id,UMOB_MAXHP,90000;setunitdata .@id,UMOB_HP,90000;
 debugmes "LOOPMOB "+.@id;end;
}
''')
c.command('@loadnpc npc/custom/qa_loop.txt')
wait(c,lambda op,b:op==0x8e and b'Script loaded' in b)
# A player standing beside an attractive group must keep it off the itinerary.
foreign=query('@loopmob 178 171',r'LOOPMOB (\d+)')
mobs=[query(f'@loopmob {x} {y}',r'LOOPMOB (\d+)') for x,y in [(162,180),(166,188),(156,196),(146,196)]]
f.note('mob radius 32')
f.note('mob 4')
log=stage/'artifacts/map-server.log'
offset=log.stat().st_size
assert 'ON' in f.note('mob on')
def trace():
    with log.open('rb') as stream:
        stream.seek(offset)
        return stream.read().decode(errors='replace')
deadline=time.monotonic()+60
while time.monotonic()<deadline:
    data=trace()
    stops=[(int(tag),int(pack),int(x),int(y)) for tag,pack,x,y in re.findall(r'Mob tour .*?tag=(\d+) pack=(\d+).*?pos=(\d+),(\d+)',data)]
    assert foreign not in {t[0] for t in stops}
    if any(tag in mobs and pack and max(abs(x-150),abs(y-180))>=5 for tag,pack,x,y in stops):break
    time.sleep(.2)
else:raise AssertionError(stops)
x,y=position(knight['name'])
warp(peer,f'prontera {x} {y}')
time.sleep(1.5)
stopped=position(knight['name'])
time.sleep(2)
assert max(abs(a-b) for a,b in zip(stopped,position(knight['name'])))<=1
assert 'มีผู้เล่นอื่น' in trace()
# An immobile aggressive Geographer appears behind the train. The route
# back to camp leads out of its footprint. It must not pin the puller here.
x,y=stopped
dx=1 if x>=150 else -1
dy=1 if y>=180 else -1
hazard=query(f'@loopmob {x+6*dx} {y+6*dy} 1368',r'LOOPMOB (\d+)')
warp(peer,'prontera 112 160')
deadline=time.monotonic()+55
while time.monotonic()<deadline:
    x,y=position(knight['name'])
    if max(abs(x-150),abs(y-180))<=4:break
    time.sleep(.2)
else:raise AssertionError((x,y))
print('PASS multiple live tags outside camp, bystander excluded, train stopped and returned past a Geographer',stops,flush=True)
peer.close()
c.close()
