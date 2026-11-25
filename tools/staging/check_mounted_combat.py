"""Measure mounted spear damage and exercise mounted Knight AI on real combat packets."""
from nearby_hunt_fixture import c,knight,mage,priest,stage,egg,hp,chat,query,damage
from check_ai_guard import target_mob_command
from companion_ai_fixture import spawn
from check_m8_gear import held,slot,transfer
from bird_fixture import BirdFixture,wait
import time
import struct
f=BirdFixture(c)
kid=knight['id']
for p in (knight,mage,priest):
    f.note(f'bench {p["id"]}')
c.command('@set BaseLevel 81')
c.command('@set JobLevel 50')
c.command('@set Zeny 5000')
c.command('@setbattleflag min_hitrate 100')
weapons={}
for item in (1157,1401):
    c.command(f'@item {item} 1')
    transfer(c,kid,slot(c,item))
    weapons[item]=held(kid)[-1][0]

path=stage/'npc/custom/qa_peco_combat.txt'
path.write_text('''-	script	QA Peco Combat	-1,{
OnInit:
 bindatcmd "pecopower",strnpcinfo(3)+"::OnPower",99,99; end;
OnPower:
 .@id=atoi(.@atcmd_parameters$[0]); if (!attachrid(.@id)) end;
 sc_start SC_MAXIMIZEPOWER,120000,1;
 debugmes "PECO_POWER "+getskilllv(55); end;
}
''')
c.command('@loadnpc npc/custom/qa_peco_combat.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
def trials(equip):
    f.note(f'summon {kid}')
    f.note(f'stop {kid}')
    actor=int(f.row(kid)[11])
    if equip:
        assert 'equipped and saved' in f.note(f'equip {kid} {weapons[1401]}')
    assert query(f'@pecopower {actor}',r'PECO_POWER (\d+)')==10
    f.note(f'skills {kid} none')
    mob=egg(153,180,1002)  # Poring, Medium
    chat('hunt on')
    def hit(i,b):
        return damage(i,b)==(0,actor,mob) and b[29]==0 and struct.unpack_from('<i',b,22)[0]>1
    val=struct.unpack_from('<i',wait(c,hit),22)[0]
    f.note(f'stop {kid}')
    c.command('@killmonster2')
    time.sleep(.8)
    return actor,val
_,foot=trials(True)
f.note(f'bench {kid}')
assert 'Saving rental' in f.note(f'rent {kid}')
f.eventually(lambda:f.row(kid)[-1]=='1')
actor,mounted=trials(False)
assert mounted>foot,(mounted,foot)
print('PASS mounted spear damage against Medium Poring',foot,mounted)
assert 'equipped and saved' in f.note(f'equip {kid} {weapons[1157]}')
f.note(f'skills {kid} quicken,bowlingbash')
mob=egg(153,180)
neighbor=egg(154,180)
log=stage/'artifacts/map-server.log'
offset=log.stat().st_size
chat('hunt on')
wait(c,lambda i,b:damage(i,b)==(62,actor,mob),20)
assert hp(neighbor)==60000
assert f'cast id={actor} skill=60' not in log.read_bytes()[offset:].decode()
print('PASS mounted Bowling Bash, protected bystander, no Two-Hand Quicken')
chat('hunt off')
c.command('@killmonster2')
f.note(f'stop {kid}')
f.note(f'skills {kid} provoke')
f.note(f'summon {mage["id"]}')
f.note(f'assist {mage["id"]}')
f.note(f'stop {mage["id"]}')
ally=int(f.row(mage['id'])[11])
target_mob_command(c)
mob,_,_=spawn(c,1002)
c.command(f'@aiguard {mob} {ally} {mage["name"]}')
wait(c,lambda i,b:damage(i,b)==(0,mob,ally))
c.command(f'@companion ui 9300 assist {kid}')
wait(c,lambda i,b:i==0x9cb and struct.unpack_from('<H',b,2)[0]==6 and struct.unpack_from('<II',b,8)==(mob,actor))
wait(c,lambda i,b:damage(i,b)==(0,mob,actor))
print('PASS mounted Provoke takes attacker off Wizard')
c.close()
