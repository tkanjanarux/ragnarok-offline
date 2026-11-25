"""Class progression and persisted presets on a disposable copy of the M9 fixture."""
import json
import pathlib
import sqlite3
import time
from protocol import login
from check_m6_profiles import api

stage = pathlib.Path('/stage')
assert (stage / 'M9_TEST').exists()
db = sqlite3.connect('file:/stage/ragoff-stage.sqlite3?mode=ro', uri=True)
def possessions():
    return [db.execute(query).fetchall() for query in (
        'SELECT id,owner_char,job FROM ragoff_companion ORDER BY id',
        'SELECT id,unique_id FROM ragoff_companion_gear ORDER BY id',
        'SELECT * FROM ragoff_companion_supply ORDER BY profile_id,nameid')]
client = login()
client.command('@setbattleflag companion_enable 1')
sequence=0
def request(action, replay=False):
    global sequence
    if not replay: sequence+=1
    client.command(f'@companion ui {sequence} ' + action + ' ui2')
    frames = []
    while True:
        code, packet = client.packet()
        if code == 0x8e:
            frame = packet[4:].rstrip(b'\0').decode()
            if frame.startswith(f'[RCO1] {sequence} '):
                frames.append(frame)
                if frame.startswith(f'[RCO1] {sequence} end '):
                    return frames
def rows():
    return {int(f[3]): f for f in (line.split() for line in request('list')) if f[2]=='row'}
client.command('@jobchange 2')
client.command('@set JobLevel 45')
time.sleep(1)
first = rows()
assert {int(f[4]) for f in first.values()} == {1,2,4}, first
pid = next(pid for pid, f in first.items() if f[4]=='4')
from check_m8_gear import slot, transfer, held, conserved
if not held(pid):
    client.command('@item 1101 1')
    transfer(client,pid,slot(client,1101))
before=possessions()
assert before[1] and before[2]
for _,uid,_,_ in held(pid): conserved(uid)
assert 'Summoned' in request(f'summon {pid}')[-1]
aid = rows()[pid][13]
assert int(aid)>0
frames=request(f'inspect {pid}')
assert not any(' skill 54 ' in f for f in frames)
(stage/'artifacts/m94-first-details.json').write_text(json.dumps(frames))
assert 'Preset saved' in request(f'preset {pid} conserve')[-1]
assert 'already handled' in request(f'preset {pid} protect',replay=True)[-1]
assert rows()[pid][-1]=='conserve'
client.command('@jobchange 9')
client.command('@set JobLevel 40')
time.sleep(1)
second=rows()
assert {int(f[4]) for f in second.values()}=={7,8,9}, second
assert second[pid][13]==aid and second[pid][-1]=='conserve'
assert any(' skill 54 ' in f and int(f.split()[4])>0 for f in request(f'inspect {pid}'))
# Issue a bench request during an actual continuous native attack.
import struct
from protocol import entry
from check_m4_exp import warp
from check_m4_skills import wait
warp(client,'prontera 150 180')
client.command('@killmonster2')
client.command('@monster 1008 1')
spawn=wait(client,lambda code,b:code in (0x9fe,0x9ff) and struct.unpack_from('<H',b,23)[0]==1008)
mob=struct.unpack_from('<I',spawn,5)[0]
warp(client,f'prontera {(spawn[63]<<2)|(spawn[64]>>6)} {((spawn[64]&63)<<4)|(spawn[65]>>4)}')
attack,_=entry('clif_parse_ActionRequest')
client.send(struct.pack('<HIB',attack,mob,7))
assert 'outside combat' in request(f'bench {pid}')[-1]
assert rows()[pid][13]==aid
client.command('@killmonster2')
time.sleep(1)
for _ in range(10):
    note=request(f'bench {pid}')[-1]
    if 'returned to reserve' in note:break
    time.sleep(.3)
else:raise AssertionError(note)
client.close()
time.sleep(2)
client=login()
assert rows()[pid][-1]=='conserve'
assert possessions()==before
legacy=api(client,'list')[0]
assert {r['job'] for r in legacy}=={7,8,9}
client.close()
print('PASS: first/second class, active identity, reserve rows, skill gate, preset reconnect, gear/stock/profile IDs and legacy roster')
