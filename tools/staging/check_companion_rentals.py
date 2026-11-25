"""Rental through native payment, warp, reserve, relog and safe Falcon combat."""
from nearby_hunt_fixture import c,knight,priest,mage,egg,hp,damage,chat,stage,query
from bird_fixture import BirdFixture,wait
from check_m4_exp import warp
from protocol import login
import time

f=BirdFixture(c)
kid=knight['id']
assert 'Reserve' in f.note(f'rent {kid}')
for p in (knight,priest,mage):
    f.note(f'bench {p["id"]}')
assert 'Recruited' in f.note('recruit hunter')
hid=int(next(t[1] for t in f.frames('list') if t[0]=='row' and t[2]=='11'))
c.command('@set BaseLevel 81')
c.command('@set JobLevel 1')
for pid in (kid,hid):
    assert 'Not enough' in f.note(f'rent {pid}')
c.command('@set JobLevel 50')
for pid in (kid,hid):
    print('Job 50',pid,f.ranks(pid),flush=True)
fixture=stage/'npc/custom/qa_bird.txt'
fixture.write_text('''-	script	QA Bird	-1,{
OnInit:
 bindatcmd "birdflag",strnpcinfo(3)+"::OnFlags",99,99; end;
OnFlags:
 .@owner=getcharid(3); .@who=atoi(.@atcmd_parameters$[0]); .@kind=atoi(.@atcmd_parameters$[1]);
 if (!attachrid(.@who)) end;
 .@on=.@kind ? checkfalcon() : checkriding();
 debugmes "NATIVE_WEIGHT "+MaxWeight; debugmes "NATIVE_BIRD "+.@on; end;
}
''')
c.command('@loadnpc npc/custom/qa_bird.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
f.note(f'summon {kid}')
unmounted=int(f.row(kid)[11])
foot_job,foot_speed=f.spawn[unmounted]
foot_weight=query(f'@birdflag {unmounted} 0',r'NATIVE_WEIGHT (\d+)')
f.note(f'bench {kid}')
c.command('@set Zeny 2000')
assert 'requires 2500' in f.note(f'rent {kid}')
c.command('@set Zeny 7500')
owner=f.db.execute('select owner_char from ragoff_companion where id=?',(kid,)).fetchone()[0]
def cash():
    return f.db.execute('select zeny from char where char_id=?',(owner,)).fetchone()[0]
for pid,money in ((kid,5000),(hid,2500)):
    note=f.note(f'rent {pid}')
    assert 'Saving rental' in note,note
    f.eventually(lambda:f.row(pid)[-1]=='1')
    assert cash()==money,cash()
    assert 'Already rented' in f.note(f'rent {pid}')
    assert cash()==money

def actor(pid):
    return int(f.row(pid)[11])
def flags(pid,mask,expected=1):
    who=actor(pid)
    assert who
    # Native status option field is exposed directly by the game script engine.
    assert query(f'@birdflag {who} {mask}',r'NATIVE_BIRD (\d+)')==expected
for pid,mode in ((kid,0),(hid,1)):
    assert 'Summoned' in f.note(f'summon {pid}')
    flags(pid,mode)
    if pid==kid:
        mounted=actor(kid)
        job,speed=f.spawn[mounted]
        weight=query(f'@birdflag {mounted} 0',r'NATIVE_WEIGHT (\d+)')
        print('Peco A/B',foot_job,job,foot_speed,speed,foot_weight,weight,flush=True)
        assert (foot_job,job)==(7,13) and speed<foot_speed and weight-foot_weight==10000
def view(pid):
    f.seq+=1
    c.command(f'@companion ui {f.seq} list ui2 hunter1 voice1 bird1 team2 hunt1')
    tag=f'[RCO1] {f.seq} '.encode()
    packet=wait(c,lambda i,b:i==0x8e and b[4:].startswith(tag+f'row {pid} '.encode()))
    wait(c,lambda i,b:i==0x8e and b[4:].startswith(tag+b'end '))
    fields=packet[4:].rstrip(b'\0').split()
    assert len(fields)==21 and fields[18]==b'1'
    return fields[20]==b'1'

for pid,mode,verb,reply in ((kid,0,'ride','dismounted'),(hid,1,'falcon','resting')):
    assert view(pid)
    c.command(f'@companion {verb} {pid} off')
    wait(c,lambda i,b:i==0x8e and reply.encode() in b)
    flags(pid,mode,0)
    assert not view(pid) and cash()==2500
assert 'Wrong companion' in f.note(f'falcon {kid} on')
from companion_ai_fixture import attack,owner as owner_actor
# A continuous player attack on a stationary target keeps combat active for
# both requests, even if native monster AI would normally switch targets.
attacker=egg(151,180)
attack(c,attacker)
wait(c,lambda i,b:damage(i,b)[1:]==(owner_actor,attacker))
assert 'outside combat' in f.note(f'ride {kid} on')
assert 'outside combat' in f.note(f'falcon {hid} on')
c.command(f'@huntremove {attacker}')
warp(c,'prontera 155 180')
for pid,mode in ((kid,0),(hid,1)):
    flags(pid,mode,0)
    f.eventually(lambda:'reserve' in f.note(f'bench {pid}').lower())
c.close()
time.sleep(2)
c=login()
import nearby_hunt_fixture
nearby_hunt_fixture.c=c
f.c=c
for pid,mode in ((kid,0),(hid,1)):
    assert f.row(pid)[-1]=='1' and cash()==2500
    f.note(f'summon {pid}')
    flags(pid,mode,0)
    verb='ride' if pid==kid else 'falcon'
    assert not view(pid)
    assert f.note(f'{verb} {pid} on') in ('Peco mounted.','Falcon active.')
    flags(pid,mode)
    assert view(pid) and cash()==2500
    f.note(f'bench {pid}')
print('PASS native rental, repeated requests, wallet, warp, reserve and relog')
c.close()
