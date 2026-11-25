"""A distant train collects a fresh monster on the way home at radius 96."""
import re
import time

from build_fixture import BuildFixture
from check_m4_exp import warp
from nearby_hunt_fixture import c, knight, mage, position, priest, query, stage, wait

assert (stage / 'STAGING_ONLY').is_file()
build = BuildFixture(c)
c.command('@set BaseLevel 88')
c.command('@set JobLevel 47')
build.note(f'bench {mage["id"]}')
build.select(mage['id'], 'storm')
build.note(f'summon {mage["id"]}')
for member in (knight, mage, priest):
    build.note(f'assist {member["id"]}')
warp(c, 'prontera 153 98')
c.command('@killmonster2')
c.command('@heal')
script = stage / 'npc/custom/qa_long_pull.txt'
script.write_text('''-	script	QA Long Pull	-1,{
OnInit: bindatcmd "longmob",strnpcinfo(3)+"::OnRun",99,99; end;
OnRun:
 .@y=atoi(.@atcmd_parameters$[0]);
 monster "prontera",153,.@y,"Pull QA",1369,1;
 .@id=$@mobid[0]; unitwarp .@id,"prontera",153,.@y;
 setunitdata .@id,UMOB_ATKMIN,1; setunitdata .@id,UMOB_ATKMAX,1;
 setunitdata .@id,UMOB_MAXHP,12000; setunitdata .@id,UMOB_HP,12000;
 debugmes "LONGMOB "+.@id;end;
}
''')
c.command('@loadnpc npc/custom/qa_long_pull.txt')
wait(c,lambda op,b:op==0x8e and b'Script loaded' in b)
def spawn_at(y):
    return query(f'@longmob {y}', r'LONGMOB (\d+)')

log=stage/'artifacts/map-server.log'
start=log.stat().st_size
def trace():
    with log.open('rb') as f:
        f.seek(start)
        return f.read().decode(errors='replace')

spawn_at(220)
build.note('mob radius 96')
build.note('mob 6')
assert 'ON' in build.note('mob on')
deadline=time.monotonic()+10
while 'ลองสำรวจทาง' not in trace() and time.monotonic()<deadline:
    time.sleep(.2)
assert 'ลองสำรวจทาง' in trace()
original={spawn_at(y) for y in (149,157,164,168)}
extra=None
peak=0
observed=set()
deadline=time.monotonic()+150
while time.monotonic()<deadline:
    x,y=position(knight['name'])
    gap=max(abs(x-153),abs(y-98))
    peak=max(peak,gap)
    if gap>=43 and extra is None:
        extra=spawn_at(128)
    rows=trace()
    observed={int(i) for i in re.findall(r'Mob escort .*?mob=(\d+) .*?role=pack',rows)}
    if extra in observed and len(original & observed)>=3 and gap<=4:
        break
    time.sleep(.4)
else:raise AssertionError((peak,original,extra,observed,x,y))
print('PASS distant groups, inbound pickup, camp hint and return',peak,len(original & observed),flush=True)
c.close()
