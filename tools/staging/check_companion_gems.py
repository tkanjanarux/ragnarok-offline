"""Real escrow and Resurrection through the transition from gift to paid stock."""
from companion_ai_fixture import setup
from bird_fixture import BirdFixture, wait
from check_m4_skills import skill
from check_m4_exp import warp
import time

c,party=setup(7)
f=BirdFixture(c)
pid=party[8]['id']
knight=party[7]
db=f.db
def balances():
    gift,owner=db.execute('select gems,owner_char from ragoff_companion where id=?',(pid,)).fetchone()
    stock=db.execute('select coalesce(sum(amount),0) from ragoff_companion_supply where profile_id=? and nameid=717',(pid,)).fetchone()[0]
    bag=db.execute('select coalesce(sum(amount),0) from inventory where char_id=? and nameid=717',(owner,)).fetchone()[0]
    return gift,stock,bag

assert 'Recruited' in f.note('recruit priest')
new=db.execute("select max(id) from ragoff_companion where job=8").fetchone()[0]
assert int(f.row(new)[13])==20,f.row(new)
# Requesting a paid return from an untouched starter grant must fail atomically.
assert 'Waiting' in f.note(f'supplytake {new} 0:717:0:1')
wait(c,lambda i,b:i==0x8e and b'Supply transfer failed' in b)
assert int(f.row(new)[13])==20 and balances()[1]==0
# Model an existing profile with just one starter gem remaining.
db.execute('update ragoff_companion set gems=1 where id=?',(pid,))
c.command('@set BaseLevel 80')
c.command('@set JobLevel 50')
c.command('@item 717 6')
time.sleep(.3)
def transfer(give,qty):
    bag=next(t for t in f.frames(f'inspect {pid}') if t[:1]==['supplybag'] and t[2]=='717')
    slot,expected=(bag[1],bag[3]) if give else (0,0)
    assert 'Waiting' in f.note(f'{"supplygive" if give else "supplytake"} {pid} {slot}:717:{expected}:{qty}')
    wait(c,lambda i,b:i==0x8e and (b'Supplies given.' if give else b'Supplies returned.') in b)
assert not any(t[0]=='supplybag' and t[2]=='717' for t in f.frames(f'inspect {knight["id"]}'))
transfer(True,5)
prior=balances()
assert prior[:2]==(1,5),prior
transfer(False,2)
assert balances()==(1,3,prior[2]+2)
warp(c,'prontera 170 180')
assert 'Summoned' in f.note(f'summon {pid}')
actor=int(f.row(pid)[11])
for gift,stock in [(0,3),(0,2)]:
    f.note(f'stop {pid}')
    c.command(f'#heal {party[8]["name"]}')
    f.note(f'assist {pid}')
    time.sleep(.5)
    c.command('@die')
    # Wait directly so the UI reply cannot swallow the resurrection packet.
    skill(c,actor,54,2000001)
    f.eventually(lambda: balances()[:2]==(gift,stock))
f.note(f'bench {pid}')
assert int(f.row(pid)[13])==0
transfer(False,2)
assert balances()==(0,0,prior[2]+4),balances()
f.eventually(lambda: db.execute('select count(*) from ragoff_companion_supply_journal').fetchone()==(0,))
print('PASS starter 20, remaining starter 1 consumed first, paid gem consumed once, escrow conservation and final return')
c.close()
