"""Prove a stocked, active Hunter leaves the puller's pack to the Wizard."""
import time

from build_fixture import BuildFixture
from companion_ai_fixture import attack
from nearby_hunt_fixture import c, damage, egg, hp, knight, mage, priest, query, stage, wait

assert (stage / 'STAGING_ONLY').is_file()
f = BuildFixture(c)
c.command('@jobchange 11')
c.command('@set BaseLevel 88')
c.command('@set JobLevel 47')
f.note(f'bench {mage["id"]}')
f.select(mage['id'], 'storm')
f.note(f'summon {mage["id"]}')
f.note('recruit hunter')
hunter, owner = f.db.execute('select id,owner_char from ragoff_companion where job=11').fetchone()
f.db.execute('insert or replace into ragoff_companion_supply values (?,?,1750,?)',(hunter,owner,150))
f.note(f'summon {hunter}')
for pid in (knight['id'],priest['id'],mage['id'],hunter):
    f.note(f'assist {pid}')
f.note(f'skills {hunter} none')
f.note(f'skills {mage["id"]} storm')
tank = int(f.row(knight['id'])[11])
archer = int(f.row(hunter)[11])
def stock():
    return f.db.execute('select amount from ragoff_companion_supply where profile_id=? and nameid=1750',(hunter,)).fetchone()[0]
source = stage/'npc/custom/qa_coordinator_pack.txt'
source.write_text('''-	script	QA Coordinator	-1,{
OnInit: bindatcmd "coordinatortest",strnpcinfo(3)+"::OnPack",99,99;end;
OnPack:
 for(.@i=0;.@i<5;.@i++){
  monster "prontera",154,180,"Coordinator",1213,1;
  .@id=$@mobid[0];unitwarp .@id,"prontera",154,180;
  setunitdata .@id,UMOB_MAXHP,400000;setunitdata .@id,UMOB_HP,400000;
  setunitdata .@id,UMOB_MODE,MD_CANMOVE|MD_CANATTACK|MD_NOCAST;
  setunitdata .@id,UMOB_ADELAY,12000;
  setunitdata .@id,UMOB_ATKMIN,1;setunitdata .@id,UMOB_ATKMAX,1;
  unitattack .@id,TANKID,1;
 }
 debugmes "COORD_PACK 5";end;
}
'''.replace('TANKID',str(tank)))
c.command('@loadnpc npc/custom/qa_coordinator_pack.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
f.note('mob 5')
f.note('mob on')
before = stock()
log = stage/'artifacts/map-server.log'
offset = log.stat().st_size
assert query('@coordinatortest',r'COORD_PACK (\d+)') == 5
end = time.monotonic()+45
while time.monotonic() < end:
    with log.open('rb') as trace:
        trace.seek(offset)
        content=trace.read()
    if content.count(b'skill=89 level=10 tick=')>=2:break
    time.sleep(.25)
assert content.count(b'skill=89 level=10 tick=')>=2
assert stock()==before, (before,stock())
f.note('mob off')
c.command('@killmonster2')
from check_m4_exp import warp
warp(c,'prontera 150 180')
f.note(f'assist {hunter}')
target=egg(151,180)
attack(c,target)
wait(c,lambda op,b:damage(op,b)[1:]==(2000001,target),16)
wait(c,lambda op,b:damage(op,b)[1:]==(archer,target),16)
assert stock()<before
print('PASS stocked Hunter held arrows for two native Storm Gust fields and resumed shooting in Assist')
c.close()
