"""A mounted or unmounted Knight must travel to an actual monster and back.
Neutral, immobile monsters by the camp test the AoE spill allowance.
"""
import os
import time
import struct
from protocol import login, entry
from check_m4_exp import warp
from nearby_hunt_fixture import c, knight, priest, mage, stage, wait, egg, query, hp, position
from build_fixture import BuildFixture

f=BuildFixture(c)
c.command('@set BaseLevel 87')
c.command('@set JobLevel 46')
f.note(f'bench {mage["id"]}')
f.select(mage['id'],'storm')
f.note(f'summon {mage["id"]}')
for row in (knight,priest,mage):f.note(f'assist {row["id"]}')
f.note(f'skills {knight["id"]} provoke')
f.note(f'skills {mage["id"]} storm')
script=stage/'npc/custom/qa_farm_lure.txt'
script.write_text('''-	script	QA Farm Lure	-1,{
OnInit: bindatcmd "farmlure",strnpcinfo(3)+"::OnRun",99,99;end;
OnRun:
 .@x=atoi(.@atcmd_parameters$[0]);
 monster "prontera",.@x,180,"Herd",1213,1;
 unitwarp $@mobid[0],"prontera",.@x,180;
 setunitdata $@mobid[0],UMOB_MAXHP,180000; setunitdata $@mobid[0],UMOB_HP,180000;
 debugmes "FARMLURE "+$@mobid[0];end;
}
''')
c.command('@loadnpc npc/custom/qa_farm_lure.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
assert '6-96' in f.note('mob radius 97')
assert 'saved' in f.note('mob radius 24')
assert 'saved' in f.note('mob 1')
# Eggs stand still and have no target, avoiding accidental counting as engaged.
neutrals=[egg(151,180) for _ in range(3)]
# Establish the other player's damage claim away from the camp and its mobs.
peer=login('/stage/peer-fixture.json')
warp(peer,'prontera 115 180')
foreign=egg(116,180,1078)
action,_=entry('clif_parse_ActionRequest')
for _ in range(14):
    peer.send(struct.pack('<HIB',action,foreign,0))
    time.sleep(.9)
    foreign_hp=hp(foreign)
    if foreign_hp<60000:break
assert foreign_hp<60000
warp(peer,'prontera 112 175')
foe=query('@farmlure 172',r'FARMLURE (\d+)')
if os.environ.get('FARM_SELF_DAMAGE') == '1':
    # Expiring Gravity Control records three points of native monster self
    # damage. Apply it before the pull so no melee hit can obscure the check.
    effect = stage/'npc/custom/qa_farm_self_damage.txt'
    effect.write_text('-\tscript\tQA Farm Self Damage\t-1,{\nOnInit: sc_start2 SC_GRAVITYCONTROL,1000,1,3,10000,1,' + str(foe) + ';end;\n}')
    c.command('@loadnpc npc/custom/qa_farm_self_damage.txt')
    wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
    deadline=time.monotonic()+12
    while hp(foe)==180000 and time.monotonic()<deadline:
        time.sleep(.2)
    assert hp(foe)==179997, 'Expected exactly three points of native self damage'
assert 'ON' in f.note('mob on')
furthest=0
returned=False
deadline=time.monotonic()+45
while time.monotonic()<deadline:
    x,y=position(knight['name'])
    d=max(abs(x-150),abs(y-180))
    furthest=max(furthest,d)
    if furthest>=12 and d<=4:
        returned=True
        break
    time.sleep(.2)
assert returned,(furthest,x,y)
# Confirm that the native monster walked back with the Knight.
trace=stage/'npc/custom/qa_farm_tail.txt'
trace.write_text('-\tscript\tQA Farm Tail\t-1,{\nOnInit: bindatcmd "farmtail",strnpcinfo(3)+"::OnRead",99,99;end;\nOnRead: getunitdata '+str(foe)+',.@s; debugmes "FARMTAIL "+distance(150,180,.@s[UMOB_X],.@s[UMOB_Y]);end;\n}')
c.command('@loadnpc npc/custom/qa_farm_tail.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
deadline=time.monotonic()+15
while time.monotonic()<deadline:
    tail=query('@farmtail',r'FARMTAIL (\d+)')
    if tail<=6:break
    time.sleep(.3)
print('knight outbound',furthest,'returned with mob distance',tail,flush=True)
assert tail<=6,tail
time.sleep(3)
assert all(hp(gid)==60000 for gid in neutrals)
if os.environ.get('FARM_WIZARD_SWITCH') == '1':
    wizard = int(f.row(mage['id'])[11])
    switch = stage/'npc/custom/qa_farm_switch.txt'
    switch.write_text(
        '-\tscript\tQA Farm Switch\t-1,{\n'
        'OnInit: bindatcmd "farmswitch",strnpcinfo(3)+"::OnSwitch",99,99; end;\n'
        f'OnSwitch: setunitdata {foe},UMOB_TARGETID,0; unitattack {foe},{wizard},1; '
        f'getunitdata {foe},.@d; debugmes "FARM SWITCH "+.@d[UMOB_TARGETID]; end;\n}}\n')
    c.command('@loadnpc npc/custom/qa_farm_switch.txt')
    wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
    assert query('@farmswitch',r'FARM SWITCH (\d+)') == wizard
    print('PASS High Orc switched to Wizard at the anchor',flush=True)
c.command(f'@huntremove {neutrals.pop()}')
allowed_at=time.monotonic()
deadline=allowed_at+30
while time.monotonic()<deadline and not all(hp(gid)<60000 for gid in neutrals):
    time.sleep(.3)
assert all(hp(gid)<60000 for gid in neutrals)
print('Storm Gust damaged both permitted bystanders after %.2fs' % (time.monotonic()-allowed_at),flush=True)
boss=egg(151,180,1039)
boss_hp=hp(boss)
# The boss enters an existing field. After removing it, the foreign claim
# independently protects the claimed target for a full native cast cycle.
time.sleep(2)
assert hp(boss)==boss_hp
move=stage/'npc/custom/qa_claimed_mob.txt'
move.write_text('-\tscript\tQA Claimed Arrival\t-1,{\nOnInit: unitwarp '+str(foreign)+',"prontera",151,180;end;\n}')
c.command('@loadnpc npc/custom/qa_claimed_mob.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
c.command(f'@huntremove {boss}')
time.sleep(9)
assert hp(foreign)==foreign_hp
c.command(f'@huntremove {foreign}')
peer.close()
# The original high-HP target survives the first cast. Leave the owner idle.
log=stage/'artifacts/map-server.log'
end=time.monotonic()+35
while time.monotonic()<end and log.read_bytes().count(b'skill=89 level=10 target=')<2:
    time.sleep(.2)
assert log.read_bytes().count(b'skill=89 level=10 target=')>=2
print('PASS Storm Gust recast on a surviving wave')
print('PASS boss entering active field and separate player claim')
print('PASS live Knight outbound/return, cap+3 withheld, cap+2 damaged',furthest,flush=True)
c.close()
