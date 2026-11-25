"""Real idle Butoijo, trap lifetime, damage and companion walking on isolated dew_dun02."""
import re
import struct
import time
from companion_ai_fixture import setup, stage, api, owner, wait, warp

c, profiles = setup()
warp(c, "dew_dun02 218 259")
c.command('@killmonster2')
c.command('@set BaseLevel 99')
c.command('@heal')
pid = profiles[7]['id']
(stage / 'npc/custom/qa_ground.txt').write_text('''-	script	QA Ground	-1,{
OnInit:
 bindatcmd "qabuto",strnpcinfo(3)+"::OnSpawn",99,99;
 bindatcmd "qawalk",strnpcinfo(3)+"::OnWalk",99,99;
 end;
OnSpawn:
 monster "dew_dun02",224,259,"QA Butoijo",2155,1;
 .@id=$@mobid[0];
 setunitdata .@id,UMOB_MODE,MD_CANATTACK;
 debugmes "QA BUTOIJO "+.@id;
 end;
OnWalk:
 .@id=atoi(.@atcmd_parameters$[0]);
 for (.@i=0; .@i<90; .@i++) {
  getmapxy .@m$,.@px,.@py,BL_PC,.@id;
  debugmes "QA_STEP "+.@id+" "+.@px+" "+.@py;
  sleep2 60;
 }
 end;
}
''')
c.command('@loadnpc npc/custom/qa_ground.txt')
wait(c, lambda i,b: i == 0x8e and b'Script loaded' in b)
log = stage / 'artifacts/map-server.log'
offset = log.stat().st_size
c.command('@qabuto')
for attempt in range(100):
    match = re.search(rb'QA BUTOIJO (\d+)', log.read_bytes()[offset:])
    if match:
        break
    time.sleep(.05)
assert match, 'test monster did not spawn'
mob = int(match[1])
entries = {}
removed = set()
damage = []
def observe(i,b):
    if i == 0x9ca:
        unit, source, x, y, kind, radius, visible, level = struct.unpack_from('<IIhhIbBB', b, 4)
        if source == mob:
            entries[unit] = (x, y, kind, radius, visible, level)
    elif i == 0x120:
        removed.add(struct.unpack_from('<I', b, 2)[0])
    elif i == 0x1de:
        skill, source, target = struct.unpack_from('<HII', b, 2)
        amount, level, hits = struct.unpack_from('<ihh', b, 24)
        if skill == 80 and amount > 0:
            damage.append((source, target, amount, hits))
read_packet = c.packet
def recorded_packet():
    i,b = read_packet()
    observe(i,b)
    return i,b
c.packet = recorded_packet

def expect(predicate, seconds=40):
    if not predicate():
        try:
            wait(c, lambda i,b: predicate(), seconds)
        except AssertionError:
            raise AssertionError((entries, removed, damage))

expect(lambda: any(v[2:] == (135,1,1,5) for v in entries.values()))
unit, (x,y,*_) = next((k,v) for k,v in entries.items() if v[2:] == (135,1,1,5))
print(f'PASS idle Butoijo {mob} placed visible Lv5 Fire Pillar {unit} at dew_dun02 ({x},{y}), radius 1', flush=True)
log = stage / 'artifacts/map-server.log'
start, end = (218,230) if x <= 224 else (230,218)
warp(c, f'dew_dun02 {start} {y}')
api(c, f'summon {pid}')
rows, _, _ = api(c, f'stop {pid}')
actor = next(r['actor'] for r in rows if r['id'] == pid)
assert actor

from protocol import entry
def walk(px,py):
    code, desc = entry('clif_parse_WalkToXY')
    packet = bytearray(desc['length'])
    struct.pack_into('<H',packet,0,code)
    at = desc['offsets'][0]
    packet[at:at+3] = bytes((px >> 2, ((px & 3) << 6) | (py >> 4), (py & 15) << 4))
    c.send(packet)
    time.sleep(2.5)

lane = 263 if y < 259 else 255
walk(start,lane)
walk(end,lane)
walk(end,y)
offset = log.stat().st_size
c.command(f'@qawalk {actor}')
api(c,f'follow {pid}')
time.sleep(6.5)
steps = [(int(a),int(b)) for a,b in re.findall(rb'QA_STEP '+str(actor).encode()+rb' (\d+) (\d+)', log.read_bytes()[offset:])]
direction = 1 if start < end else -1
assert steps and (steps[0][0]-x)*direction < -1 and (steps[-1][0]-x)*direction >= 2, steps
assert all(max(abs(px-x),abs(py-y)) > 1 for px,py in steps), steps
print('PASS companion followed its owner around the live 3x3 trigger area',list(dict.fromkeys(steps)),flush=True)
api(c,f'bench {pid}')
assert unit not in removed and not any(t == actor for _,t,_,_ in damage), (unit,removed,damage)
# Use a fresh idle cast for damage attribution; the original lasts only 30s.
c.command('@killmonster2')
warp(c, 'dew_dun02 218 259')
offset = log.stat().st_size
c.command('@qabuto')
for attempt in range(100):
    match = re.search(rb'QA BUTOIJO (\d+)', log.read_bytes()[offset:])
    if match:
        break
    time.sleep(.05)
assert match
mob = int(match[1])
entries.clear()
expect(lambda: any(v[2:] == (135,1,1,5) for v in entries.values()))
unit, (x,y,*_) = next((k,v) for k,v in entries.items() if v[2:] == (135,1,1,5))
walk(x,y)
expect(lambda: unit in removed and any(t == owner and n > 1 for _,t,_,n in damage))
assert any(t == owner and n == 7 and entries.get(source, ())[:3] == (x, y, 136) for source,t,amount,n in damage), damage
print('PASS player triggered real multi-hit Fire Pillar and original unit disappeared', damage, flush=True)
c.close()
