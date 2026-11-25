"""Retain the exact first-job ranks across native Hunter promotion, reserve and login."""
import pathlib
import re
import time

from check_m4_skills import wait
from check_m6_profiles import api
from protocol import login

assert pathlib.Path('/stage/M9_TEST').exists()
client = login()
client.command('@setbattleflag companion_enable 1')
api(client, 'party')
profiles = {row['job']:row['id'] for row in api(client, 'list')[0]}
first = {7:(5,6,8), 8:(28,34,29,33), 9:(19,14,20)}
second = {7:{62:15}, 8:{74:15,54:20}, 9:{90:15,84:20}}
seq = 1000

def table(pid):
    global seq
    seq += 1
    client.command(f'@companion ui {seq} inspect {pid} ui2 skills4 gear2 syrup1 hunt1')
    skills = {}
    while True:
        _, msg = client.until({0x8e})
        parts = msg[4:].rstrip(b'\0').split()
        if parts[:2] != [b'[RCO1]', str(seq).encode()]:
            continue
        if parts[2] == b'end':
            return skills
        if parts[2] == b'skill':
            skills[int(parts[3])] = int(parts[4])

def active_skills():
    client.command('@companion status')
    result = {}
    for _ in profiles:
        data = wait(client, lambda i,b: i==0x8e and b'Companion loadout id=' in b)
        aid = int(re.search(rb'id=(\d+)',data)[1])
        result[aid] = {int(k):int(v) for k,v in re.findall(rb'skill(\d+)=(\d+)',data)}
    return result

def check(ranks, jl, active):
    actors = {r['id']:r['actor'] for r in api(client,'list')[0]}
    native = active_skills() if active else {}
    for line,pid in profiles.items():
        displayed = table(pid)
        assert {i:displayed[i] for i in first[line]} == ranks[line], (line,displayed,ranks)
        for i,gate in second[line].items():
            assert displayed[i] == (0 if jl < gate else 1+(jl-gate)//(10 if i==54 else 5)), (i,jl,displayed)
        if active:
            assert all(native[actors[pid]][i]==v for i,v in displayed.items()), (line,displayed,native)
        else:
            assert not actors[pid]

for promotion in (40,50):
    client.command('@jobchange 3')  # Archer
    client.command(f'@set JobLevel {promotion}')
    time.sleep(.8)
    ranks = {line:{i:table(pid)[i] for i in first[line]} for line,pid in profiles.items()}
    assert ranks[7][5] == 10  # Bowling Bash requires Bash 10 before normal promotion
    for pid in profiles.values():
        assert 'Summoned' in api(client,f'summon {pid}')[1]
        api(client,f'stop {pid}')
    client.command('@jobchange 11')  # Hunter, native reset to Job 1
    time.sleep(.9)
    assert all(r['job_level']==1 for r in api(client,'list')[0])
    check(ranks,1,True)
    for jl in (14,15,19,20,1):
        client.command(f'@set JobLevel {jl}')
        time.sleep(.7)
        check(ranks,jl,True)
    for pid in profiles.values():
        assert 'reserve' in api(client,f'bench {pid}')[1]
    check(ranks,1,False)
    client.close()
    time.sleep(1)
    client=login()
    check(ranks,1,False)
    print('PASS Hunter promotion at',promotion,'all three lines, native/displayed ranks, Job 1/14/15/19/20, reserve and relog:',ranks,flush=True)
client.close()
