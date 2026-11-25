"""Exercise native class-two casts, weapon/water restrictions, unlocks and collateral damage."""
import struct
import time

from nearby_hunt_fixture import api, c, egg, hp, knight, mage, priest, stage, wait
from check_ai_guard import target_mob_command
from check_m8_gear import held, slot, transfer
from companion_ai_fixture import owner, spawn

c.command('@set BaseLevel 90')
c.command('@jobchange 3')
c.command('@set JobLevel 50')
c.command('@jobchange 11')
schedule = {7:{56:6,60:12,59:50},8:{66:1,73:25,75:45},9:{86:32}}
seq = 9000
for jl in (1,5,6,11,12,24,25,31,32,44,45,49,50):
    c.command(f'@set JobLevel {jl}')
    time.sleep(.55)
    for job, member in ((7,knight),(8,priest),(9,mage)):
        seq += 1
        c.command(f"@companion ui {seq} inspect {member['id']} ui2 skills5 gear2 syrup1 hunt1")
        learned = {}
        while True:
            _,msg=c.until({0x8e})
            parts=msg[4:].rstrip(b'\0').split()
            if parts[:2]!=[b'[RCO1]',str(seq).encode()]: continue
            if parts[2]==b'end': break
            if parts[2]==b'skill': learned[int(parts[3])]=tuple(map(int,parts[4:7]))
        for skill,gate in schedule[job].items():
            lv,cap,unlock=learned[skill]
            expected=min(cap,1+(jl-gate)//5) if jl>=gate else 0
            if skill==60 and jl>=15: expected=10  # Bowling Bash prerequisite
            assert unlock==gate and lv==expected,(jl,skill,learned)
print('PASS Job 1–50 skill rows and ranks for all three classes',flush=True)

def mode(member, action):
    return api(c,f"{action} {member['id']}")[1]

def choose(member,key):
    assert f'skills={key}' in api(c,f"skills {member['id']} {key}")[1]
    c.command(f"#heal {member['name']}")

def buff(skill, recipient):
    wait(c,lambda i,b:i==0x9cb and struct.unpack_from('<H',b,2)[0]==skill and struct.unpack_from('<I',b,8)[0]==recipient and b[16]!=0,15)

target_mob_command(c)
for key,skill in [('impositio',66),('gloria',75)]:
    choose(priest,key)
    c.command(f"@companion ui 801 assist {priest['id']}")
    buff(skill,owner)
    print('PASS native party buff',key,flush=True)
    mode(priest,'stop')
choose(priest,'kyrie,heal')
mode(mage,'assist')
mode(mage,'stop')
mob,_,_=spawn(c,1002)
c.command(f"@aiguard {mob} {mage['actor']} {mage['name']}")
wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(mob,mage['actor']))
c.command('@set Hp 1')
c.command(f"@companion ui 802 assist {priest['id']}")
buff(28,owner)
c.command('@heal')
buff(73,mage['actor'])
print('PASS Heal before Kyrie; native shield on attacked Wizard',flush=True)
c.command('@killmonster2')
mode(priest,'stop')
time.sleep(1)
for member in (priest,mage,knight):
    assert 'reserve' in mode(member,'bench')

weapons={}
for item in (1157,1401):
    c.command(f'@item {item} 1')
    transfer(c,knight['id'],slot(c,item))
    weapons[item]=held(knight['id'])[-1][0]
assert 'Summoned' in mode(knight,'summon')
mode(knight,'stop')

def hunt(member,key):
    choose(member,key)
    target=egg(153,180)
    other=egg(154,180)
    c.command('@companion hunt on')
    return target,other

def damage(skill,actor,mob):
    wait(c,lambda i,b:i==0x1de and struct.unpack_from('<HII',b,2)==(skill,actor,mob) and struct.unpack_from('<i',b,24)[0]>0,18)

def finish(member,other):
    mode(member,'stop')
    assert hp(other)==60000
    c.command('@killmonster2')
    time.sleep(1.5)

# With only the starter knife, the Knight must use basic attacks even with
# all three new weapon skills enabled.
actor=next(r['actor'] for r in api(c,'list')[0] if r['id']==knight['id'])
log=stage/'artifacts/map-server.log'
offset=log.stat().st_size
target,other=hunt(knight,'quicken,pierce,spearboomerang')
wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(actor,target),15)
with log.open('rb') as f:
    f.seek(offset)
    assert f'cast id={actor} '.encode() not in f.read()
finish(knight,other)
print('PASS starter knife suppresses all three weapon skills',flush=True)

for key,skill,item in [('quicken',60,1157),('pierce',56,1401),('spearboomerang',59,1401)]:
    if key!='spearboomerang':
        assert 'equipped and saved' in api(c,f"equip {knight['id']} {weapons[item]}")[1]
    actor=next(r['actor'] for r in api(c,'list')[0] if r['id']==knight['id'])
    target,other=hunt(knight,key)
    if skill==60: buff(skill,actor)
    else: damage(skill,actor,target)
    finish(knight,other)
    print('PASS native',key,'idle neighbor unharmed',flush=True)
assert 'reserve' in mode(knight,'bench')
mode(mage,'summon')
actor=next(r['actor'] for r in api(c,'list')[0] if r['id']==mage['id'])
path=stage/'npc/custom/qa_water_skill.txt'
path.write_text('-\tscript\tQA Water\t-1,{\nOnInit: bindatcmd "qawater",strnpcinfo(3)+"::OnWater",99,99; end;\nOnWater: setcell "prontera",136,166,164,194,CELL_WATER,atoi(.@atcmd_parameters$[0]); if (getarraysize(.@atcmd_parameters$)>1) setunitdata atoi(.@atcmd_parameters$[1]),UMOB_HP,20; end;\n}\n')
c.command('@loadnpc npc/custom/qa_water_skill.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
for wet in (0,1):
    c.command(f'@qawater {wet}')
    target,other=hunt(mage,'waterball,coldbolt')
    damage(86 if wet else 14,actor,target)
    deadline=time.monotonic()+5
    while hp(target)==60000:
        assert time.monotonic()<deadline, 'damage did not reach the target'
        time.sleep(.1)
    mode(mage,'stop')
    time.sleep(.8)
    stop_hp=hp(target)
    time.sleep(2)
    assert hp(target)==stop_hp and hp(other)==60000
    c.command('@killmonster2')
    print('PASS', 'Water Ball on water' if wet else 'Cold Bolt on dry land','Stop and unengaged neighbor',flush=True)
choose(mage,'waterball')
target=egg(153,180)
c.command(f'@qawater 1 {target}')
assert hp(target)==20
offset=log.stat().st_size
c.command('@companion hunt on')
damage(86,actor,target)
with log.open('rb') as f:
    f.seek(offset)
    assert any(f'skill=86 target={target} '.encode() in line and line.rstrip().endswith(b'level=1') for line in f)
print('PASS Water Ball chooses level 1 against 20 remaining HP',flush=True)
c.close()
print('PASS expanded class-two combat',flush=True)
