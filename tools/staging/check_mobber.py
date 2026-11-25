"""Exercise the negotiated iPhone protocol, training, puller selection and live aggro."""
import time
import os
import struct
from build_fixture import BuildFixture
from nearby_hunt_fixture import c, knight, priest, mage, stage, query, wait, egg
from check_ai_guard import target_mob_command
from check_m4_exp import warp

assert (stage/'STAGING_ONLY').is_file()

class PullerFixture(BuildFixture):
    def frames(self, action):
        self.seq += 1
        self.c.command(f'@companion ui {self.seq} {action} ui2 skills9 gear3 syrup1 hunter1 voice1 bird1 puller1 team2 hunt1')
        rows=[]
        while True:
            packet=wait(self.c,lambda op,b:op==0x8e and b[4:].startswith(f'[RCO1] {self.seq} '.encode()))
            row=packet[4:].rstrip(b'\0').decode().split()[2:]
            rows.append(row)
            if row[0]=='end':return rows

f=PullerFixture(c)
pid=priest['id']
for member in (priest,mage,knight):f.note(f'bench {member["id"]}')
c.command('@jobchange 3')
def build(key):
    assert f.note(f'build {pid} {key}').startswith('Build: '+key)
    assert f.row(pid)[17]==key
build('mobber')
for job in (1,5,10,20,30,40,50):
    c.command(f'@set JobLevel {job}')
    print('ACOLYTE_JOB',job,f.ranks(pid),flush=True)
build('support')
c.command('@set JobLevel 50')
c.command('@jobchange 11')
c.command('@set BaseLevel 88')
c.command('@set JobLevel 47')
support=f.ranks(pid)
build('mobber')
for job in (1,5,10,20,30,40,47,50):
    c.command(f'@set JobLevel {job}')
    ranks=f.ranks(pid)
    assert ranks[25]==1 and ranks[27]==4 and ranks[31]==1,ranks
    if ranks[12]:assert ranks[68]>=4 and ranks[70]>=3 and ranks[66]>=3
    print('PRIEST_JOB',job,ranks,flush=True)
c.command('@set JobLevel 47')
build('support')
assert f.ranks(pid)==support
build('mobber')
assert 'Build: storm' in f.note(f'build {mage["id"]} storm')
for member in (priest,mage,knight):
    assert 'Summoned' in f.note(f'summon {member["id"]}')
    f.note(f'assist {member["id"]}')
c.command('@heal')
def select(key):
    assert 'saved' in f.note('mob puller '+key)
    assert next(t for t in f.frames('list') if t[0]=='team')[-1]==key
select('knight')
select('priest')
select('auto')
f.note('mob radius 30')
f.note('mob 1')
actor=int(f.row(pid)[11])
script=stage/'npc/custom/qa_mobber.txt'
script.write_text('''-	script	QA Mobber	-1,{
OnInit: bindatcmd "mobberlure",strnpcinfo(3)+"::OnLure",99,99;
 bindatcmd "mobberhurt",strnpcinfo(3)+"::OnHurt",99,99;
 bindatcmd "mobberread",strnpcinfo(3)+"::OnRead",99,99;end;
OnLure:
 monster "prontera",173,180,"Mobber QA",1213,1; .id=$@mobid[0];unitwarp .id,"prontera",173,180;
 setunitdata .id,UMOB_MAXHP,250000;setunitdata .id,UMOB_HP,250000;
 debugmes "MOBBER_TARGET "+.id;end;
OnHurt: percentheal -80,0;debugmes "MOBBER_HURT "+Hp;end;
OnRead:
 getunitdata .id,.@u; debugmes "MOBBER_AGGRO "+.@u[UMOB_TARGETID];end;
}
''')
c.command('@loadnpc npc/custom/qa_mobber.txt')
wait(c,lambda op,b:op==0x8e and b'Script loaded' in b)
query('@mobberlure',r'MOBBER_TARGET (\d+)')
assert 'ON' in f.note('mob on')
assert 'off' in f.note('mob puller knight')
end=time.monotonic()+45
while query('@mobberread',r'MOBBER_AGGRO (\d+)')!=actor:
    assert time.monotonic()<end
    time.sleep(.2)
print('PASS auto selected the mobber and the real monster targeted the Priest',flush=True)
# The owner is at camp and the sole healer is outside. Verify a native Heal
# on the owner after the health change, not just the decision to turn back.
log=stage/'artifacts/map-server.log'
offset=log.stat().st_size
query('@mobberhurt',r'MOBBER_HURT (\d+)')
deadline=time.monotonic()+20
while True:
    with log.open('rb') as trace:
        trace.seek(offset)
        if f'cast id={actor} skill=28 target=2000001 '.encode() in trace.read():break
    assert time.monotonic()<deadline
    time.sleep(.15)
print('PASS puller returned and healed critically injured owner',flush=True)

f.note('mob off')
c.command('@killmonster2')
if os.environ.get('MOBBER_WARDS'):
    target_mob_command(c)
    f.note(f'skills {pid} heal,kyrie,agi,safetywall,pneuma')
    for species,unit,cost in [(1002,126,1),(1020,133,0)]:
        warp(c,'prontera 150 180' if unit==126 else 'prontera 158 184')
        c.command('@heal')
        assert 'ON' in f.note('mob on')
        mid=egg(150,181,species)
        def gems():
            return f.db.execute('select gems from ragoff_companion where id=?',(pid,)).fetchone()[0]
        before=gems()
        c.command(f'@aiguard {mid} {actor} {priest["name"]}')
        wait(c,lambda op,b:op==0x9ca and struct.unpack_from('<i',b,16)[0]==unit,15)
        assert before-gems()==cost
        print('PASS mobber native ward',unit,'gem cost',cost,flush=True)
        c.command(f'@huntremove {mid}')
        f.note('mob off')
f.note(f'bench {pid}')
build('support')
f.note(f'summon {pid}')
f.note(f'assist {pid}')
select('priest')
assert 'Puller Priest' in f.note('mob on')
select('auto')
assert 'ON' in f.note('mob on')
print('PASS explicit priest rejects support, auto retains Knight, support ranks restored')
c.close()
