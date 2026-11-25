"""A caster must wait while its owner approaches a fresh passive monster."""
import pathlib
import socket
import struct
import time

from check_m4_exp import warp
from check_m4_skills import wait
from check_m6_profiles import api
from protocol import entry, login


def bolt(code, packet, caster, target, skill):
    if code in (0x13e, 0x7fb, 0xb1a):
        return (struct.unpack_from('<II', packet, 2) == (caster, target)
                and struct.unpack_from('<H', packet, 14)[0] == skill)
    return code == 0x1de and struct.unpack_from('<HII', packet, 2) == (skill, caster, target)


assert pathlib.Path('/stage/M9_TEST').exists()
fixture = pathlib.Path('/stage/npc/custom/qa_egg_mode.txt')
fixture.write_text('-\tscript\tQA Egg Mode\t-1,{\nOnInit: bindatcmd "qaeggmode",strnpcinfo(3)+"::OnMode",99,99; end;\n'
                   'OnMode: setunitdata atoi(.@atcmd_parameters$[0]),UMOB_MODE,MD_NOCAST; end;\n}\n')
client = login()
client.command('@loadnpc npc/custom/qa_egg_mode.txt')
wait(client,lambda i,b:i==0x8e and b'Script loaded' in b)
client.command('@setbattleflag companion_enable 1')
client.command('@jobchange 1')
client.command('@heal')
warp(client, 'prontera 150 180')
client.command('@killmonster2')
api(client, 'party')
row = next(r for r in api(client, 'list')[0] if r['job'] in (2, 9))
profile = row['id']
assert 'Summoned' in api(client, f'summon {profile}')[1]
actor = next(r for r in api(client, 'list')[0] if r['id'] == profile)['actor']
assert api(client, f'assist {profile}')[1] == 'Assisting.'
attack, _ = entry('clif_parse_ActionRequest')
for owner_job, key, skill, monster in (
    (1, "firebolt", 19, 1078), (1, "coldbolt", 14, 1078), (7, "lightningbolt", 20, 1078),
    (7, "earthspike", 90, 1078), (7, "jupitelthunder", 84, 1078),
    (1, "coldbolt,lightningbolt,firebolt", 19, 1078),  # Earth 1
    (1, "coldbolt,lightningbolt,firebolt", 20, 1142),  # Water 2
    (1, "coldbolt,lightningbolt,firebolt", 14, 1097),  # Neutral: preserve order
    (7, "earthspike,coldbolt", 14, 1078),              # Fire Bolt disabled
):
    client.command(f'@jobchange {owner_job}')
    client.command('@set JobLevel 20')
    time.sleep(.6)
    assert f'skills={key}' in api(client, f'skills {profile} {key}')[1]
    client.command('@heal')
    warp(client, 'prontera 150 180')  # Start each spawn in the same open area.
    client.command(f'@monster {monster} 1')
    spawn = wait(client, lambda i,b: i in (0x9fe, 0x9ff) and struct.unpack_from('<H', b, 23)[0] == monster)
    mob = struct.unpack_from('<I', spawn, 5)[0]
    if monster == 1097:  # Keep the neutral Ant Egg from hatching into an Earth monster.
        client.command(f'@qaeggmode {mob}')
    x = (spawn[63] << 2) | (spawn[64] >> 6)
    y = ((spawn[64] & 63) << 4) | (spawn[65] >> 4)
    warp(client, f'prontera {x+5} {y}')
    time.sleep(1.5)
    client.send(struct.pack('<HIB', attack, mob, 7))
    wait(client, lambda i,b: i == 0x139 and struct.unpack_from('<I', b, 2)[0] == mob)
    client.s.settimeout(.2)
    until = time.monotonic() + 2
    while time.monotonic() < until:
        try:
            code, packet = client.packet()
        except socket.timeout:
            continue
        assert not any(bolt(code, packet, actor, mob, candidate) for candidate in (14, 19, 20, 84, 90)), 'caster opened before melee contact'
    client.s.settimeout(10)
    warp(client, f'prontera {x} {y}')
    client.send(struct.pack('<HIB', attack, mob, 7))
    wait(client, lambda i,b: i == 0x8c8 and struct.unpack_from('<II', b, 2) == (2000001, mob))
    def first_spell(i, packet):
        for candidate in (14, 19, 20, 84, 90):
            if bolt(i,packet,actor,mob,candidate):
                assert candidate == skill, (key, candidate, skill)
                return True
        return False
    wait(client, first_spell)
    print(f'PASS class {owner_job}, mob {monster}, enabled {key}: first cast {skill} after contact', flush=True)
    client.command('@killmonster2')
    time.sleep(.5)
for seq, suffix, expected in ((800, 'ui2', {19}), (801, 'ui2 skills2', {14, 19, 20}),
                              (802, 'ui2 skills4', {14, 19, 20, 84, 90})):
    client.command(f'@companion ui {seq} inspect {profile} {suffix}')
    reported = set()
    while True:
        frame = wait(client, lambda i,b: i == 0x8e and f'[RCO1] {seq} '.encode() in b)
        fields = frame[4:].rstrip(b'\0').decode().split()
        if fields[2] == 'skill':
            reported.add(int(fields[3]))
            assert int(fields[4]) > 0 and int(fields[7]) > 0
        if fields[2] == 'end':
            break
    assert reported == expected, reported
# Demotion on the same live actor removes Wizard-only skills.
client.command('@jobchange 1')
client.command('@set JobLevel 40')
time.sleep(.6)
client.command(f'@companion ui 803 inspect {profile} ui2 skills4')
mage_skills = set()
while True:
    packet = wait(client, lambda i,b: i == 0x8e and b'[RCO1] 803 ' in b)
    fields = packet[4:].rstrip(b'\0').split()
    if fields[2] == b'skill':
        mage_skills.add(int(fields[3]))
    if fields[2] == b'end':
        break
assert mage_skills == {14, 19, 20}, mage_skills
client.close()
