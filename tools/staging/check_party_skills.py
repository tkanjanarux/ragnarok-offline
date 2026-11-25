"""Verify class gating, unlock levels and native effects in the disposable M9 runtime."""
import itertools
import pathlib
import sqlite3
import struct
import time

from check_m4_exp import warp
from check_m4_skills import wait
from check_m6_profiles import api
from protocol import entry, login

assert pathlib.Path('/stage/M9_TEST').exists()
# The transition fixture can leave a profile dead or out of SP.
with sqlite3.connect('/stage/ragoff-stage.sqlite3') as fixture:
    fixture.execute('UPDATE ragoff_companion SET hp=g.max_hp,sp=g.max_sp FROM ragoff_companion_growth AS g WHERE g.profile_id=ragoff_companion.id')
client = login()
client.command('@setbattleflag companion_enable 1')
warp(client, 'prontera 150 180')
api(client, 'party')
seq = itertools.count(1000)
rows = api(client, 'list')[0]
sword = next(r['id'] for r in rows if r['job'] in (1, 7))
priest = next(r['id'] for r in rows if r['job'] in (4, 8))


def details(profile):
    token = next(seq)
    client.command(f'@companion ui {token} inspect {profile} ui2 skills3')
    skills = {}
    while True:
        packet = wait(client, lambda i,b: i == 0x8e and f'[RCO1] {token} '.encode() in b)
        fields = packet[4:].rstrip(b'\0').split()
        if fields[2] == b'skill':
            skill, level, maximum, unlock, sp, reason = map(int, fields[3:])
            skills[skill] = level, maximum, unlock
        if fields[2] == b'end':
            return skills


for job, level in ((1,9), (1,10), (7,14), (7,15)):
    client.command(f'@jobchange {job}')
    client.command(f'@set JobLevel {level}')
    time.sleep(.6)
    for profile, first, second, maximum in ((sword,8,62,10), (priest,33,74,5)):
        skills = details(profile)
        # This fixture promotes at first-job level 10, freezing its first-job ranks.
        inherited_level = level if job == 1 else 10
        assert skills[first] == (int(inherited_level>=10), 10, 10), skills
        if job == 1:
            assert second not in skills, skills
        else:
            assert skills[second] == (int(level>=15), maximum, 15), skills

for profile, cases in ((sword, [('endure',8), ('bowlingbash',62)]),
                       (priest, [('angelus',33), ('magnificat',74)])):
    result = api(client, f'summon {profile}')[1]
    assert 'Summoned' in result, result
    actor = next(r['actor'] for r in api(client,'list')[0] if r['id']==profile)
    for key, skill in cases:
        api(client, f'stop {profile}')
        assert f'skills={key}' in api(client, f'skills {profile} {key}')[1]
        row = next(r for r in api(client,'list')[0] if r['id']==profile)
        client.command(f"#heal {row['name']}")
        if profile == sword:
            client.command('@monster 1078 1')
            spawn = wait(client, lambda i,b: i in (0x9fe,0x9ff) and struct.unpack_from('<H',b,23)[0]==1078)
            mob = struct.unpack_from('<I',spawn,5)[0]
            x = (spawn[63]<<2) | (spawn[64]>>6)
            y = ((spawn[64]&63)<<4) | (spawn[65]>>4)
            warp(client,f'prontera {x} {y}')
        # Send without draining the socket so instant casts remain observable.
        client.command('@companion assist')
        if profile == sword:
            attack,_ = entry('clif_parse_ActionRequest')
            client.send(struct.pack('<HIB',attack,mob,7))
        if skill == 62:
            wait(client, lambda i,b: i==0x1de and struct.unpack_from('<HII',b,2)==(skill,actor,mob))
        else:
            target = actor if skill == 8 else 2000001
            wait(client, lambda i,b: i==0x9cb and struct.unpack_from('<H',b,2)[0]==skill and struct.unpack_from('<I',b,8)[0]==target and b[16]==1)
        print('PASS', key, flush=True)
        client.command('@killmonster2')
        time.sleep(.6)
    api(client, f'stop {profile}')
    warp(client, 'prontera 150 180')
    api(client, f'bench {profile}')
    time.sleep(6)  # Let the owner's post-warp invulnerability end before party buffs.
client.close()
