"""Isolate the AI ground-cast path using explicit test-only ranks on a real Priest."""
import sqlite3
import struct
from nearby_hunt_fixture import c,priest,knight,egg,stage,wait
from build_fixture import BuildFixture
from check_ai_guard import target_mob_command
from check_m4_exp import warp

f=BuildFixture(c)
target_mob_command(c)
for member in (priest,knight):f.note(f'assist {member["id"]}')
f.note(f'skills {priest["id"]} heal,safetywall,pneuma')
f.note(f'skills {knight["id"]} none')
script=stage/'npc/custom/qa_ward_ranks.txt'
script.write_text('''-	script	QA ward ranks	-1,{
OnInit: bindatcmd "qawardgrant",strnpcinfo(3)+"::OnGrant",99,99; end;
OnGrant:
 if(!attachrid(atoi(.@atcmd_parameters$[0]))) end;
 skill "MG_SAFETYWALL",5; skill "AL_PNEUMA",1; end;
}
''')
c.command('@loadnpc npc/custom/qa_ward_ranks.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
c.command(f'@qawardgrant {priest["actor"]}')
db=sqlite3.connect(stage/'ragoff-stage.sqlite3')
def gems():
    return db.execute('select gems from ragoff_companion where id=?',(priest['id'],)).fetchone()[0]
for species,unit,expected_cost in ((1002,126,1),(1020,133,0)):
    warp(c,'prontera 150 180' if unit==126 else 'prontera 158 184')
    c.command(f'@qawardgrant {priest["actor"]}')
    assert f.note('mob on')=='Mob mode ON.'
    mob=egg(150,181,species)
    before=gems()
    c.command(f'@aiguard {mob} {knight["actor"]} {knight["name"]}')
    wait(c,lambda i,b:i==0x9ca and struct.unpack_from('<i',b,16)[0]==unit,12)
    assert before-gems()==expected_cost,(before,gems())
    print('PASS provisional QA ranks, native ground unit',unit,'gem cost',expected_cost,flush=True)
    c.command(f'@huntremove {mob}')
    f.note('mob off')
c.close()
