"""Find the actual paid skill unlocks without borrowing points from prior ranks."""
from companion_ai_fixture import setup
from bird_fixture import BirdFixture
c,party=setup()
f=BirdFixture(c)
f.note('recruit hunter')
kid=party[7]['id']
hid=int(next(t[1] for t in f.frames('list') if t[0]=='row' and t[2]=='11'))
c.command('@jobchange 3')
c.command('@set JobLevel 50')
c.command('@jobchange 11')
c.command('@set BaseLevel 83')
gates={}
last={}
for level in range(1,51):
    c.command(f'@set JobLevel {level}')
    ranks=f.ranks(kid)|f.ranks(hid)
    birds={k:ranks[k] for k in (63,64,127,129,128)}
    assert all(birds[k]>=last.get(k,0) for k in birds)
    for k,v in birds.items():
        if v and k not in gates:
            gates[k]=level
    if level in (39,50):
        print('Job',level,birds,flush=True)
    last=birds
assert last=={63:1,64:5,127:1,129:5,128:10} and len(gates)==5
print('PASS training gates',gates)
c.close()
