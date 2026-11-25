"""Check what an owner actually receives when an unmounted Protect Knight buffs."""
import struct
from nearby_hunt_fixture import c, knight, priest, mage, egg, query, stage
from bird_fixture import BirdFixture, wait
from companion_ai_fixture import attack, owner
from check_m8_gear import held, slot, transfer

f = BirdFixture(c)
pid = knight['id']
for profile in (knight, priest, mage):
    f.note(f'bench {profile["id"]}')
c.command('@jobchange 11')
c.command('@set BaseLevel 83')
c.command('@set JobLevel 39')
c.command('@item 1157 1')
transfer(c, pid, slot(c, 1157))
c.command('@set Zeny 5000')
assert 'Saving rental' in f.note(f'rent {pid}')
f.eventually(lambda:f.row(pid)[-1]=='1')
f.note(f'summon {pid}')
assert 'dismounted' in f.note(f'ride {pid} off')
f.note(f'stop {pid}')
assert 'equipped and saved' in f.note(f'equip {pid} {held(pid)[-1][0]}')
f.note(f'preset {pid} protect')
assert 'skills=quicken' in f.note(f'skills {pid} quicken')
assert f.ranks(pid)[60] == 10
actor = int(f.row(pid)[11])
script = stage/'npc/custom/qa_quicken.txt'
script.write_text('''-	script	QA Quicken	-1,{
OnInit:
 bindatcmd "qacheckquicken",strnpcinfo(3)+"::OnStatus",99,99; end;
OnStatus:
 .@id=atoi(.@atcmd_parameters$[0]); if (!attachrid(.@id)) end;
 debugmes "QUICKEN_RANK "+getstatus(SC_TWOHANDQUICKEN,1); end;
}
''')
c.command('@loadnpc npc/custom/qa_quicken.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
def active_rank():
    return query(f'@qacheckquicken {actor}',r'QUICKEN_RANK (\d+)')

f.note(f'assist {pid}')
assert active_rank()==0
mob=egg(152,180)
attack(c,mob)
wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(owner,mob))
p=wait(c,lambda i,b:i==0x9cb and struct.unpack_from('<H',b,2)[0]==60)
assert struct.unpack_from('<iII',p,4)==(10,actor,actor) and p[16]==1,p.hex()
assert active_rank()==10
print('PASS Protect/Assist, successful owner packet 0x09cb level 10, source equals target Knight, native SC_TWOHANDQUICKEN rank 10')
c.close()
