"""The Hunter must shoot a threat at camp while the puller is still outside."""
import sqlite3
import time
from nearby_hunt_fixture import c, knight, priest, mage, stage, wait, damage, position, query
from check_ai_guard import target_mob_command
from build_fixture import BuildFixture

assert (stage/'STAGING_ONLY').is_file()
f=BuildFixture(c)
c.command('@set BaseLevel 87')
c.command('@set JobLevel 46')
f.note(f'bench {mage["id"]}')
f.select(mage['id'],'storm')
f.note(f'summon {mage["id"]}')
assert 'Recruited' in f.note('recruit hunter')
with sqlite3.connect(stage/'ragoff-stage.sqlite3') as db:
    pid,owner=db.execute('select id,owner_char from ragoff_companion where job=11').fetchone()
    db.execute('insert into ragoff_companion_supply values (?,?,1750,50)',(pid,owner))
f.note(f'summon {pid}')
for key in (knight['id'],priest['id'],mage['id'],pid):
    f.note(f'assist {key}')
hunter=int(f.row(pid)[11])
wizard=f.row(mage['id'])
target_mob_command(c)
script=stage/'npc/custom/qa_escort_hunter.txt'
script.write_text('''-	script	QA Escort Hunter	-1,{
OnInit: bindatcmd "escortspawn",strnpcinfo(3)+"::OnSpawn",99,99;end;
OnSpawn:
 .@x=atoi(.@atcmd_parameters$[0]);
 monster "prontera",.@x,180,"Escort Hunter QA",1369,1;
 .@m=$@mobid[0];unitwarp .@m,"prontera",.@x,180;
 debugmes "ESCORT NEW "+.@m;end;
}
''')
c.command('@loadnpc npc/custom/qa_escort_hunter.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
pull=query('@escortspawn 178',r'ESCORT NEW (\d+)')
f.note('mob radius 40')
assert 'ON' in f.note('mob on')
deadline=time.monotonic()+25
while time.monotonic()<deadline:
    x,y=position(knight['name'])
    if x>=167:break
    time.sleep(.15)
assert x>=167,(x,y)
stray=query('@escortspawn 150',r'ESCORT NEW (\d+)')
# Native AI may switch targets on the next tick. Repeat the threat if the
# Knight immediately peels it, and require an observed Hunter damage packet.
for attempt in range(3):
    c.command(f'@aiguard {stray} {wizard[11]} {wizard[14]}')
    try:
        wait(c,lambda i,b:damage(i,b)[1:]==(hunter,stray),3)
    except AssertionError:
        continue
    break
else:raise AssertionError(f'Hunter {hunter} did not hit backline attacker {stray}')
print('PASS Hunter hit the Wizard attacker while the Knight was pulling',flush=True)
c.close()
