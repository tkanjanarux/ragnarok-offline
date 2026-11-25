"""Disambiguate commanded Blitz from auto Blitz with the AI policy and bow attacks."""
import time
from nearby_hunt_fixture import c,knight,mage,priest,egg,hp,chat,damage,stage,query
from bird_fixture import BirdFixture,wait

f=BirdFixture(c)
for profile in (knight,mage,priest):
    f.note(f'bench {profile["id"]}')
c.command('@set BaseLevel 81')
c.command('@set JobLevel 50')
c.command('@set Zeny 5000')
c.command('@setbattleflag min_hitrate 100')
f.note('recruit hunter')
pid=int(next(t[1] for t in f.frames('list') if t[0]=='row' and t[2]=='11'))
assert 'Saving rental' in f.note(f'rent {pid}')
f.eventually(lambda:f.row(pid)[-1]=='1')
f.db.execute('insert into ragoff_companion_supply select id,owner_char,1750,100 from ragoff_companion where id=?',(pid,))
f.note(f'summon {pid}')
actor=int(f.row(pid)[11])
path=stage/'npc/custom/qa_falcon_combat.txt'
path.write_text('''-	script	QA Falcon Combat	-1,{
OnInit:
 bindatcmd "falconluck",strnpcinfo(3)+"::OnLuck",99,99; end;
OnLuck:
 .@actor=atoi(.@atcmd_parameters$[0]);
 if (!attachrid(.@actor)) end;
 sc_start SC_INCLUK,120000,350;
 debugmes "FALCON_LUK "+getstatus(SC_INCLUK,1); end;
}
''')
c.command('@loadnpc npc/custom/qa_falcon_combat.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
assert 'resting' in f.note(f'falcon {pid} off')
assert query(f'@falconluck {actor}',r'FALCON_LUK (\d+)')>=300
off_target=egg(155,180)
f.note(f'skills {pid} blitz')
chat('hunt on')
# Observe bow hits at guaranteed auto-Blitz LUK while the active skill is also enabled.
bow_hits=0
end=time.monotonic()+20
while bow_hits<5 and time.monotonic()<end:
    p=wait(c,lambda i,b:damage(i,b)[1:]==(actor,off_target),8)
    assert damage(int.from_bytes(p[:2],'little'),p)[0]!=129
    bow_hits+=1
assert bow_hits==5
chat('hunt off')
c.command(f'@huntremove {off_target}')
assert 'active' in f.note(f'falcon {pid} on')
print('PASS resting Falcon suppresses both forms of Blitz while Hunter keeps shooting')
target=egg(155,180)
f.note(f'skills {pid} blitz')
chat('hunt on')
wait(c,lambda i,b:damage(i,b)==(129,actor,target),20)
print('PASS native commanded Blitz against single engaged target')
f.note(f'skills {pid} none')
assert query(f'@falconluck {actor}',r'FALCON_LUK (\d+)')>=300
wait(c,lambda i,b:damage(i,b)==(129,actor,target),20)
print('PASS native automatic Blitz with active skill disabled')
bystander=egg(156,180)
f.note(f'skills {pid} blitz')
before=hp(target)
time.sleep(5)
assert hp(target)<before and hp(bystander)==60000,(before,hp(target),hp(bystander))
c.command(f'@huntremove {bystander}')
wait(c,lambda i,b:damage(i,b)==(129,actor,target),20)
print('PASS adjacent unengaged mob takes zero damage, Blitz resumes after clearance')
c.close()
