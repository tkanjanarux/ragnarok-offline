"""A second game connection sees the same actor and text with a stricter area throttle."""
from companion_ai_fixture import setup, stage
from bird_fixture import BirdFixture,wait
from check_m4_exp import warp
from protocol import login
import struct,time,socket

c,profiles=setup()
f=BirdFixture(c)
peer=login(str(stage/'peer-fixture.json'))
warp(peer,'prontera 150 180')
peer.s.settimeout(.3)
pid=profiles[7]['id']
assert f.note('talk chatty')=='Team speech: chatty'
f.note(f'summon {pid}')
actor=int(f.row(pid)[11])
def hear():
    packet=wait(peer,lambda i,b:i==0x8d and struct.unpack_from('<I',b,4)[0]==actor,18)
    return time.monotonic(),packet[8:].rstrip(b'\0').decode()
start,hello=hear()
assert ' : ' in hello
# Trigger when the 8-second flavor line is still useful at send time.
time.sleep(4)
assert 'ON' in f.note('hunt on')
second,first=hear()
assert second-start>=9.5,(start,second)
assert any(p in first for p in ('ออกล่า','ล่าใกล้'))
for _ in range(2):
    f.note('hunt off')
    f.note('hunt on')
deadline=second+29
while time.monotonic()<deadline:
    try: i,b=peer.packet()
    except socket.timeout: continue
    if i==0x8d and struct.unpack_from('<I',b,4)[0]==actor:
        assert not any(p in b[8:].decode() for p in ('ออกล่า','ล่าใกล้')),b
f.note('hunt off')
time.sleep(4)
f.note('hunt on')
third,another=hear()
if not any(p in another for p in ('ออกล่า','ล่าใกล้')):
    third,another=hear()
assert any(p in another for p in ('ออกล่า','ล่าใกล้')) and another!=first,(first,another)
print('PASS nearby client receives public bubble, 10s bystander throttle, 30s event cooldown, different next phrase')
peer.close()
c.close()
