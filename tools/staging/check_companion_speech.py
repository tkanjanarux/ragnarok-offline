"""Observe actual public chat packets, speaker IDs and timing on a disposable server."""
import socket
import struct
import time
from companion_ai_fixture import setup
from bird_fixture import BirdFixture, wait
from protocol import login

c, profiles = setup()
f = BirdFixture(c)
seen = []
read_packet = c.packet

def record():
    code, packet = read_packet()
    if code == 0x8d:
        actor, = struct.unpack_from('<I', packet, 4)
        if 95000000 <= actor < 100000000:
            message = packet[8:].rstrip(b'\0').decode('utf-8', errors='strict')
            name, phrase = message.split(' : ', 1)
            assert name and any('\u0e01' <= ch <= '\u0e5b' for ch in phrase)
            seen.append((time.monotonic(), actor, phrase))
    return code, packet

c.packet = record
c.s.settimeout(.2)

def listen(seconds, done=lambda: False):
    deadline = time.monotonic()+seconds
    while time.monotonic()<deadline and not done():
        try: c.packet()
        except socket.timeout: pass

def direct(mode):
    c.command(('@companion talk '+mode).rstrip())
    return wait(c,lambda i,b:i==0x8e and b'Team speech:' in b)[4:].strip(b'\0').decode()

def ui(mode):
    f.seq += 1
    c.command(f'@companion ui {f.seq} list ui2 hunter1 voice1 hunt1')
    tag=f'[RCO1] {f.seq} '.encode()
    wait(c,lambda i,b:i==0x8e and tag+b'voice '+mode.encode()+b'\0' in b)
    wait(c,lambda i,b:i==0x8e and tag+b'end ' in b)

assert direct('')=='Team speech: normal'
ui('normal')
f.note('recruit hunter')
hid=int(next(t[1] for t in f.frames('list') if t[0]=='row' and t[2]=='11'))
pid=profiles[8]['id']
for profile,item in ((hid,1750),(hid,501),(hid,505),(pid,717)):
    f.db.execute('insert into ragoff_companion_supply select id,owner_char,?,20 from ragoff_companion where id=?',(item,profile))
f.db.execute('update ragoff_companion set gems=0 where id=?',(pid,))
for p in (hid,pid):
    assert 'Summoned' in f.note(f'summon {p}')
actors={int(f.row(p)[11]) for p in (hid,pid)}
listen(4)
# Four resources run out while other messages hold the team/personal cooldowns.
f.db.execute('update ragoff_companion_supply set amount=0 where profile_id in (?,?)',(hid,pid))
expected=[
    ('ลูกธนูหมด','เติมลูกธนู','แล่งธนูว่าง'),
    ('ยาฟื้น HP หมด','ขอยาเติมเลือด','ไม่เหลือยาฮีล'),
    ('ยาฟื้น SP หมด','ขอยาเติม SP','ยาเติมพลังหมด'),
    ('หินฟ้าหมด','ขอ Blue Gemstone','ไม่มีหินฟ้า')
]
def alerts():
    return [sum(any(token in msg for token in group) for _,_,msg in seen) for group in expected]
listen(43,lambda: alerts()==[1]*4)
assert alerts()==[1]*4, seen
assert all(actor in actors for _,actor,_ in seen)
assert all(b[0]-a[0]>=4.7 for a,b in zip(seen,seen[1:])),seen
print('PASS four concurrent critical alerts delivered in UTF-8, identified speakers, 5s team throttle',flush=True)
assert direct('off')=='Team speech: off'
ui('off')
n=len(seen)
f.note(f'bench {hid}')
f.note(f'summon {hid}')
listen(7)
assert len(seen)==n,seen[n:]
assert f.note('talk chatty')=='Team speech: chatty'
ui('chatty')
assert direct('quiet')=='Team speech: quiet'
c.close()
time.sleep(2)
c=login()
f.c=c
ui('quiet')
print('PASS off suppresses speech, chat/UI change frequency and character preference survives relog',flush=True)
c.close()
