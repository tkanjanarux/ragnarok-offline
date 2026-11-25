"""Verify live actor skills and gear across second class, rebirth, and promotion."""
import json
import pathlib
import re
import time

from protocol import login
from check_m4_skills import wait
from check_m6_profiles import api
from check_m8_gear import conserved, held

root = pathlib.Path('/stage')
assert (root / 'M9_TEST').exists()
client = login()
client.command('@setbattleflag companion_enable 1')
client.command('@setbattleflag natural_healhp_interval 3600000')
client.command('@setbattleflag natural_healsp_interval 3600000')
client.command('@jobchange 9')
client.command('@set JobLevel 40')
rows = api(client, 'list')[0]
for row in rows:
    _, note, _ = api(client, f'summon {row["id"]}')
    assert 'Summoned' in note, note
    api(client, f'stop {row["id"]}')
rows = api(client, 'list')[0]
profile_ids = {row['id']:row['actor'] for row in rows}
by_line = {row['job']:row for row in rows}
proof = []
for owner_class, expected in [(2, {7:1,8:4,9:2}), (4054, {7:7,8:8,9:9})]:
    for row in api(client, 'list')[0]:
        client.command(f'#set {row["name"]} Hp {row["max_hp"]//2}')
    time.sleep(.4)
    before = {row['id']:row for row in api(client,'list')[0]}
    client.command(f'@jobchange {owner_class}')
    client.command('@set JobLevel 40')
    time.sleep(1)
    after = api(client,'list')[0]
    assert {row['id']:row['actor'] for row in after} == profile_ids
    for row in after:
        old=before[row['id']]
        assert (row['hp']==0)==(old['hp']==0) and abs(row['hp']/row['max_hp']-old['hp']/old['max_hp'])<.025,(row,old)
        for _,uid,_,_ in held(row['id']):conserved(uid)
    client.command('@companion status')
    skills, classes = {},{}
    while len(skills)<3 or len(classes)<3:
        data=wait(client,lambda i,b:i==0x8e and (b'Companion loadout id=' in b or b'Companion id=' in b))
        message=data[4:].decode().strip('\x00')
        aid=int(re.search(r'id=(\d+)',message)[1])
        if 'loadout id=' in message:
            skills[aid]=dict((int(k),int(v)) for k,v in re.findall(r'skill(\d+)=(\d+)',message))
        else:
            classes[aid]=int(re.search(r'class=(\d+)',message)[1])
    for line,actual in expected.items():
        aid=by_line[line]['actor']
        assert classes[aid]==actual,(classes,expected)
        assert skills[aid][{7:5,8:28,9:19}[line]]>0
    assert (skills[by_line[8]['actor']][54]>0)==(expected[8]==8)
    proof.append({'owner':owner_class,'actor_classes':classes,'live_resurrection':skills[by_line[8]['actor']][54]})
for row in rows:
    _,note,_=api(client,f'bench {row["id"]}')
    assert 'returned to reserve' in note,note
client.close()
(root/'artifacts/m94-transitions.json').write_text(json.dumps(proof,indent=2))
print('PASS: three live actors through demotion and promotion, native skill levels, HP ratios and gear UIDs')
