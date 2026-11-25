"""Induce an aggro break and a backline switch during a live pull in an isolated fixture."""
import time
import os
from nearby_hunt_fixture import c, knight, priest, mage, stage, wait, query
from build_fixture import BuildFixture

assert (stage/'STAGING_ONLY').is_file()
f=BuildFixture(c)
c.command('@set BaseLevel 87')
c.command('@set JobLevel 46')
f.note(f'bench {mage["id"]}')
f.select(mage['id'],'storm')
f.note(f'summon {mage["id"]}')
for row in (knight,priest,mage):
    f.note(f'assist {row["id"]}')
f.note(f'skills {knight["id"]} provoke')
kid=int(f.row(knight['id'])[11])
log=stage/'artifacts/map-server.log'
script=stage/'npc/custom/qa_herd.txt'
script.write_text('''-	script	QA Herd	-1,{
OnInit:
 bindatcmd "herdplace",strnpcinfo(3)+"::OnPlace",99,99;
 bindatcmd "herdread",strnpcinfo(3)+"::OnRead",99,99;
 bindatcmd "herdcage",strnpcinfo(3)+"::OnCage",99,99;
 bindatcmd "herdbreak",strnpcinfo(3)+"::OnBreak",99,99;
 end;
OnPlace:
 .@x=atoi(.@atcmd_parameters$[0]);if(!.@x).@x=172;
 monster "prontera",.@x,180,"Escort QA",1369,1;
 .mob=$@mobid[0]; unitwarp .mob,"prontera",.@x,180;
 setunitdata .mob,UMOB_MAXHP,180000;setunitdata .mob,UMOB_HP,180000;
 setunitdata .mob,UMOB_SPEED,400;
 debugmes "ESCORT ID "+.mob;end;
OnRead:
 getunitdata .mob,.@u;
 debugmes "ESCORT POS "+.@u[UMOB_X]+" "+.@u[UMOB_Y]+" "+.@u[UMOB_TARGETID];end;
OnCage:
 for(.@x=154;.@x<=156;.@x++)for(.@y=179;.@y<=181;.@y++)
  if(.@x!=155 || .@y!=180){
   setcell "prontera",.@x,.@y,.@x,.@y,cell_walkable,0;
   setcell "prontera",.@x,.@y,.@x,.@y,cell_shootable,0;
  }
 unitwarp .mob,"prontera",155,180;
 setunitdata .mob,UMOB_MODE,MD_NOCAST|MD_KNOCKBACKIMMUNE;
 setunitdata .mob,UMOB_TARGETID,0;
 debugmes "ESCORT CAGE 1";end;
OnBreak:
 .@victim=atoi(.@atcmd_parameters$[0]);
 setunitdata .mob,UMOB_TARGETID,0;
 if(.@victim)unitattack .mob,.@victim,1;
 getunitdata .mob,.@u;
 debugmes "ESCORT BREAK "+.@u[UMOB_TARGETID];end;
}
''')
c.command('@loadnpc npc/custom/qa_herd.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
mid=query('@herdplace',r'ESCORT ID (\d+)')
f.note('mob radius 30')
f.note('mob 1')
assert 'ON' in f.note('mob on')
def victim():
    return query('@herdread',r'ESCORT POS \d+ \d+ (\d+)')
def await_tank(seconds):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        if victim()==kid:return
        time.sleep(.15)
    raise AssertionError('Knight did not recover aggro')
await_tank(30)
time.sleep(.45)
assert query('@herdbreak 0',r'ESCORT BREAK (\d+)')==0
await_tank(6)
print('PASS retag after losing aggro',flush=True)
# A melee hit may retake the first switch while Provoke is on cooldown.
# Repeat the switch after each native cooldown and verify a real cast.
for attempt in range(3):
    time.sleep(1.6)
    offset=log.stat().st_size
    assert query('@herdbreak 2000001',r'ESCORT BREAK (\d+)')==2000001
    await_tank(8)
    with log.open('rb') as stream:
        stream.seek(offset);text=stream.read().decode()
    if f'cast id={kid} skill=6 target={mid}' in text:break
else:raise AssertionError('backline rescue never cast Provoke')
print('PASS Provoke after backline switch',flush=True)
deadline=time.monotonic()+25
while time.monotonic()<deadline:
    x=query('@herdread',r'ESCORT POS (\d+)')
    if x<=157:break
    time.sleep(.2)
assert x<=157,x
print('PASS slow follower reached the anchor',flush=True)
# A live, unreachable monster five cells from camp used to occupy a slot
# indefinitely when its aggro ended. No player or companion can hit the cage.
start=time.monotonic()
offset=log.stat().st_size
assert query('@herdcage',r'ESCORT CAGE (\d+)')==1
replacement=query('@herdplace 132',r'ESCORT ID (\d+)')
assert replacement!=mid
release=None
reacquired=None
while time.monotonic()-start<25:
    if release is None:
        with log.open('rb') as stream:
            stream.seek(offset)
            if f'lost={mid} '.encode() in stream.read():release=time.monotonic()-start
    if victim()==kid:
        reacquired=time.monotonic()-start
        break
    time.sleep(.1)
print('Abandoned slot release log:',release,'replacement monster tagged:',reacquired,flush=True)
if os.environ.get('ESCORT_OBSERVE_BASELINE')!='1':
    assert release is not None and release<8,release
    assert reacquired is not None,reacquired
    print('PASS abandoned slot released and filled by a new pull',flush=True)
c.close()
