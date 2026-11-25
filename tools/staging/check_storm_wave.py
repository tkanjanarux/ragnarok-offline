"""Check opening rank and successive native fields against sustained packs."""
import re
import time

from build_fixture import BuildFixture
from nearby_hunt_fixture import c, knight, mage, priest, query, stage, wait

f = BuildFixture(c)
c.command('@set BaseLevel 87')
c.command('@set JobLevel 46')
f.note(f'bench {mage["id"]}')
f.select(mage['id'], 'storm')
f.note(f'summon {mage["id"]}')
for member in (knight, priest, mage):
    f.note(f'assist {member["id"]}')
f.note(f'skills {mage["id"]} storm')
f.note(f'skills {priest["id"]} heal,kyrie')
tank = int(f.row(knight['id'])[11])
npc = stage / 'npc/custom/qa_storm_wave.txt'
npc.write_text('''-	script	QA Storm Wave	-1,{
OnInit: bindatcmd "stormwave",strnpcinfo(3)+"::OnRun",99,99; end;
OnRun:
 for (.@i=0;.@i<atoi(.@atcmd_parameters$[1]);.@i++) {
  monster "prontera",151,180,"Wave QA",atoi(.@atcmd_parameters$[0]),1;
  .@id=$@mobid[0]; unitwarp .@id,"prontera",151,180;
  setunitdata .@id,UMOB_MAXHP,500000; setunitdata .@id,UMOB_HP,500000;
  if(atoi(.@atcmd_parameters$[1])>3){
   setunitdata .@id,UMOB_MODE,MD_CANMOVE|MD_CANATTACK|MD_NOCAST;
   setunitdata .@id,UMOB_ADELAY,12000;
   setunitdata .@id,UMOB_ATKMIN,1; setunitdata .@id,UMOB_ATKMAX,1;
  }
  unitattack .@id,TANKID,1;
 }
 debugmes "STORM_TEST_READY 1"; end;
}
'''.replace('TANKID', str(tank)))
c.command('@loadnpc npc/custom/qa_storm_wave.txt')
wait(c, lambda i,b: i == 0x8e and b'Script loaded' in b)
log = stage / 'artifacts/map-server.log'
for species, count, opener in [(1213, 3, 1), (1015, 3, 10), (1213, 6, 10)]:
    c.command('@killmonster2')
    c.command('@heal')
    for member in (knight,priest,mage):
        c.command(f'#heal {member["name"]}')
    f.note(f'mob {count}')
    before_on = log.stat().st_size
    f.note('mob on')
    with log.open('rb') as trace:
        trace.seek(before_on)
        anchor = re.search(rb'anchor=(\d+),(\d+) cap=',trace.read())
    assert anchor, 'Missing encounter anchor'
    ax,ay = map(int,anchor.groups())
    offset = log.stat().st_size
    query(f'@stormwave {species} {count}', r'STORM_TEST_READY (\d+)')
    deadline = time.monotonic() + 65
    while time.monotonic() < deadline:
        with log.open('rb') as trace:
            trace.seek(offset)
            data = trace.read().decode(errors='replace')
        fields = [(int(skill), int(lv), int(t)) for skill,lv,t in re.findall(
            r'Mob field landed wizard=\d+ skill=(\d+) level=(\d+) tick=(\d+)', data)]
        storms = [(lv,t) for skill,lv,t in fields if skill == 89]
        if len(storms) >= 2 and any(skill == 92 for skill,_,_ in fields):
            break
        time.sleep(.4)
    assert [lv for lv,_ in storms[:2]] == [opener,10], (species,fields)
    assert storms[1][1] - storms[0][1] >= 4500, fields
    assert any(skill == 92 and lv > 0 for skill,lv,_ in fields), fields
    positions = re.findall(r'Mob wizard .*?pos=(\d+),(\d+).*?reason=cast-start',data)
    assert any(8 <= max(abs(int(x)-ax),abs(int(y)-ay)) <= 10 for x,y in positions), positions
    print('PASS species',species,'pack',count,'native fields',fields,'cast positions',positions,flush=True)
    f.note('mob off')
    c.command('@killmonster2')
    time.sleep(7)
c.close()
