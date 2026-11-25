"""Exercise a fourth recruit with real arrow escrow and native ranged attacks."""
import sqlite3
import time
from nearby_hunt_fixture import c, egg, hp, knight, priest, mage, position, chat, damage, stage, wait
from protocol import login

seq = 7000
def frames(action, replay=False):
    global seq
    if not replay:
        seq += 1
    caps = 'ui2 skills6 gear2 syrup1' if action.startswith('inspect ') else 'ui2'
    c.command(f'@companion ui {seq} {action} {caps} hunter1 hunt1')
    result = []
    while True:
        _, raw = c.until({0x8e})
        parts = raw[4:].rstrip(b'\0').decode().split()
        if parts[:2] == ['[RCO1]',str(seq)]:
            result.append(parts[2:])
            if parts[2]=='end':
                return result

def note(action):
    return ' '.join(frames(action)[-1][1:])
def inspect():
    return frames(f'inspect {pid}')
def ranks():
    return {int(t[1]):int(t[2]) for t in inspect() if t[0]=='skill'}
def stock():
    return {int(t[1]):int(t[2]) for t in inspect() if t[0]=='supply'}
def transfer(item, amount, giving):
    bag={int(t[2]):(int(t[1]),int(t[3])) for t in inspect() if t[0]=='supplybag'}
    slot, count=bag[item] if giving else (0,0)
    action=f'{"supplygive" if giving else "supplytake"} {pid} {slot}:{item}:{count}:{amount}'
    assert 'Waiting' in note(action)
    wait(c,lambda i,b:i==0x8e and (b'Supplies given.' if giving else b'Supplies returned.') in b)
    assert 'already handled' in ' '.join(frames(action,True)[-1])
def inventory(item):
    return db.execute('SELECT coalesce(sum(amount),0) FROM inventory WHERE char_id=(SELECT owner_char FROM ragoff_companion WHERE id=?) AND nameid=?',(pid,item)).fetchone()[0]

assert 'Recruited' in note('recruit hunter')
row=next(t for t in frames('list') if t[0]=='row' and t[2]=='11')
pid=int(row[1])
assert 'Summoned' in note(f'summon {pid}')
assert 'reserve' in note(f'bench {pid}').lower()
assert next(t for t in frames('list') if t[:2]==['row',str(pid)])[11]=='0'
for old in (knight,priest,mage):
    assert 'reserve' in note(f"bench {old['id']}").lower()
c.command('@jobchange 3')
for level,expected in [(2,{43:0,44:0,45:0,46:1}), (6,{43:3,44:1,45:0,46:1}), (7,{43:3,44:1,45:1,46:1}), (50,{43:10,44:10,45:10,46:10})]:
    c.command(f'@set JobLevel {level}')
    assert ranks()==expected,(level,ranks())
assert any(t[:3]==['row',str(pid),'3'] for t in frames('list'))
c.command('@jobchange 11')
c.command('@set JobLevel 2')
assert ranks()=={43:10,44:10,45:10,46:10,126:1},ranks()
print('PASS roster, active cap, first job ranks and promotion')
db=sqlite3.connect(stage/'ragoff-stage.sqlite3',isolation_level=None)
for item in (1750,1752):
    c.command(f'@item {item} 9')
    time.sleep(.15)
    transfer(item,7,True)
    transfer(item,1,False)
    assert stock()[item]==6 and inventory(item)>=3
start={item:inventory(item)+stock()[item] for item in (1750,1752)}
assert 'Summoned' in note(f'summon {pid}')
actor=int(next(t for t in frames('list') if t[:2]==['row',str(pid)])[11])
assert actor
assert ['starter','0','1701','1'] in inspect()
note(f'assist {pid}')
target=egg(157,180,1010) # Earth Willow
other=egg(158,181,1002)
time.sleep(1)
assert hp(target)==60000 and hp(other)==60000
chat('hunt on')
# Hold the stock balance constant: a rejected debit must never deliver damage.
# The first hit can be in flight while testing Stop, so test the rejection on a fresh target below.
wait(c,lambda i,b:damage(i,b)==(46,actor,target),18)
print('PASS native Double Strafe')
note(f'stop {pid}')
held=stock()
assert held.get(1752,0)<6 and held[1750]==6,held
assert hp(other)==60000
assert max(abs(a-b) for a,b in zip(position(row[14]),(157,180)))>=3
c.command('@killmonster2')
target=egg(156,180,1010)
db.execute("CREATE TRIGGER hunter_reject BEFORE UPDATE OF amount ON ragoff_companion_supply WHEN new.amount<old.amount BEGIN SELECT RAISE(FAIL,'fixture'); END")
try:
    note(f'skills {pid} none')
    chat('hunt on')
    time.sleep(3)
    assert hp(target)==60000 and stock()==held
finally:
    db.execute('DROP TRIGGER hunter_reject')
# Each accepted native normal attack must consume exactly one arrow.
# There are no other attackers. Double Strafe is disabled for this interval.
seen=0
deadline=time.monotonic()+30
while time.monotonic()<deadline:
    code,packet=c.packet()
    if damage(code,packet)==(0,actor,target):
        seen+=1
    if code==0x8e and b'Out of arrows' in packet:
        break
else:
    raise AssertionError('no empty quiver notification')
assert seen==sum(held.values()),(seen,held)
assert not stock(),stock()
time.sleep(1)
held_hp=hp(target)
time.sleep(2)
assert held_hp<60000 and hp(target)==held_hp
note(f'bench {pid}')
c.close()
time.sleep(.6)
c=login()
assert not stock()
assert all(inventory(item)+6==start[item] for item in start)
print('PASS element selection, ranged attacks, untouched bystander, rejected debit, empty quiver, reconnect conservation')
c.close()
