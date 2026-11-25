"""Inspect both roster protocols and the native hit order on an isolated four-career team."""
import sqlite3
import struct
import time

from protocol import login
from check_m4_exp import warp
from nearby_hunt_fixture import c, knight, mage, priest, api, egg, hp, damage, stage, wait, chat

seq=8000
def request(action):
    global seq
    seq+=1
    c.command(f'@companion ui {seq} {action} ui2 hunter1 hunt1')
    frames=[]
    while True:
        _,b=c.until({0x8e})
        t=b[4:].rstrip(b'\0').split()
        if t[:2]!=[b'[RCO1]',str(seq).encode()]:continue
        frames.append(t[2:])
        if t[2]==b'end':return frames

def rows():
    return {int(t[1]):(int(t[2]),int(t[11])) for t in request('list') if t[0]==b'row'}

assert 'Recruited' in api(c,'recruit hunter')[1]
hunter=next(pid for pid,(job,_) in rows().items() if job==11)
db=sqlite3.connect(stage/'ragoff-stage.sqlite3',isolation_level=None)
db.execute('insert into ragoff_companion_supply select id,owner_char,1750,100 from ragoff_companion where id=?',(hunter,))
# Roster replies and the native party update share a socket. A UI request
# may consume the party packet before its command acknowledgement arrives.
updates=[]
original_packet=c.packet
def record_party():
    op,b=original_packet()
    if op==0xae5:updates.append(b)
    return op,b
c.packet=record_party
assert 'Summoned' in api(c,f'summon {hunter}')[1]
roster=rows()
actors={j:a for j,a in roster.values()}
assert len(actors)==4 and all(actors.values())
c.packet=original_packet
def complete_party(b):
    return all(struct.pack('<II',a,a) in b for a in actors.values()) and b'StageOwner' in b
p=next((packet for packet in updates if complete_party(packet)),None)
if p is None:p=wait(c,lambda i,b:i==0xae5 and complete_party(b))
assert all(p.count(struct.pack('<II',a,a))==1 for a in actors.values())
assert 'Recruited' in api(c,'recruit priest')[1]
fifth=next(pid for pid,(_,a) in rows().items() if not a)
assert 'four per owner' in api(c,f'summon {fifth}')[1]
c.command('@companion add knight')
wait(c,lambda i,b:i==0x8e and b'Maximum four' in b)
assert rows()[fifth][1]==0
print('PASS Party packet has owner plus four distinct actors; UI has four active and fifth in reserve; both summon paths enforce cap')
for pid,skills in [(priest['id'],'none'),(knight['id'],'bash'),(mage['id'],'firebolt'),(hunter,'none')]:
    api(c,f'skills {pid} {skills}')

def fight(opener,attackers):
    c.command('@killmonster2')
    target=egg(152,180)
    other=egg(156,180,1078)
    # Retain every packet after enabling hunt, including the first hit.
    c.command('@companion hunt on')
    seen=set()
    def landed(i,b):
        _,src,dst=damage(i,b)
        if src not in actors.values():return False
        assert dst==target,(src,dst,target)
        if not seen:assert src==actors[opener],(src,opener)
        seen.add(src)
        return seen=={actors[job] for job in attackers}
    wait(c,landed,25)
    assert hp(other)==60000
    chat('hunt off')
    c.command('@killmonster2')
    for pid,(job,aid) in rows().items():
        if aid: api(c,f'stop {pid}')
    time.sleep(.8)
    print('PASS opener',opener,'shared target for',attackers)
fight(7,[7,9,11])
assert 'reserve' in api(c,f"bench {knight['id']}")[1].lower()
fight(9,[9,11])
api(c,f"skills {mage['id']} none")
fight(11,[11])  # Wizard is active but has no enabled attack.
assert 'reserve' in api(c,f"bench {mage['id']}")[1].lower()
fight(11,[11])
assert 'reserve' in api(c,f'bench {hunter}')[1].lower()
c.command('@killmonster2')
target=egg(152,180)
chat('hunt on')
time.sleep(2)
assert hp(target)==60000
chat('hunt off')
for pid in (knight['id'],mage['id'],fifth):
    assert 'Summoned' in api(c,f'summon {pid}')[1]
assert sum(a!=0 for j,a in rows().values())==4 and rows()[hunter][1]==0
print('PASS Priest alone waits; swapping from Reserve restores four active')
chat('hunt on')
warp(c,'izlude 128 114')
assert [b'hunt',b'0'] in request('list')
assert sum(a!=0 for j,a in rows().values())==4
c.close()
time.sleep(1)
c=login()
assert [b'hunt',b'0'] in request('list')
assert len(rows())==5 and all(a==0 for j,a in rows().values())
print('PASS four active across warp; reconnect keeps all five profiles in Reserve and hunt off')
c.close()
