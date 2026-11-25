"""Observe native Kyrie before departure, then remove the shield during the pull."""
import re
import time

from build_fixture import BuildFixture
from nearby_hunt_fixture import c, knight, mage, priest, stage, query, wait

assert (stage/'STAGING_ONLY').is_file()
f = BuildFixture(c)
c.command('@set BaseLevel 88')
c.command('@set JobLevel 47')
c.command('@heal')
f.note(f'bench {mage["id"]}')
f.select(mage['id'],'storm')
f.note(f'summon {mage["id"]}')
for member in (knight,priest,mage):
    f.note(f'assist {member["id"]}')
f.note(f'skills {priest["id"]} heal,kyrie')
tank = int(f.row(knight['id'])[11])
healer = int(f.row(priest['id'])[11])
script = stage/'npc/custom/qa_pull_kyrie.txt'
script.write_text('''-	script	QA Pull Kyrie	-1,{
OnInit:
 bindatcmd "kyriepull",strnpcinfo(3)+"::OnPull",99,99;
 bindatcmd "kyrieclear",strnpcinfo(3)+"::OnClear",99,99;
 bindatcmd "kyriecheck",strnpcinfo(3)+"::OnCheck",99,99; end;
OnClear: sc_end SC_KYRIE,KID; debugmes "KYRIE_CLEARED "+getstatus(SC_KYRIE,1,KID); end;
OnCheck: debugmes "KYRIE_LEVEL "+getstatus(SC_KYRIE,1,KID); end;
OnPull:
 monster "prontera",172,180,"Kyrie QA",1213,1;
 unitwarp $@mobid[0],"prontera",172,180;
 setunitdata $@mobid[0],UMOB_MAXHP,200000; setunitdata $@mobid[0],UMOB_HP,200000;
 debugmes "KYRIE_PULL "+$@mobid[0]; end;
}
'''.replace('KID',str(tank)))
c.command('@loadnpc npc/custom/qa_pull_kyrie.txt')
wait(c,lambda op,b:op==0x8e and b'Script loaded' in b)
f.note('mob radius 24')
f.note('mob 1')
query('@kyriepull',r'KYRIE_PULL (\d+)')
assert query('@kyrieclear',r'KYRIE_CLEARED (\d+)') == 0
log = stage/'artifacts/map-server.log'
offset = log.stat().st_size
assert 'ON' in f.note('mob on')
def trace():
    with log.open('rb') as stream:
        stream.seek(offset)
        return stream.read().decode(errors='replace')
deadline = time.monotonic()+25
while 'role=pack' not in trace():
    assert time.monotonic()<deadline,trace()[-3000:]
    time.sleep(.15)
data=trace()
casts=fr'Companion M4: cast id={healer} skill=73 target={tank} '
assert re.search(casts,data[:data.index('role=pack')]), data[-4000:]
assert query('@kyrieclear',r'KYRIE_CLEARED (\d+)') == 0
offset = log.stat().st_size
deadline = time.monotonic()+25
while not re.search(casts,trace()) or not query('@kyriecheck',r'KYRIE_LEVEL (\d+)'):
    assert time.monotonic()<deadline,trace()[-3000:]
    time.sleep(.2)
print('PASS Kyrie cast before the first tag and restored on the Knight during the same pull')
c.close()
