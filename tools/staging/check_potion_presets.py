import time
from companion_ai_fixture import api
from potion_ai_fixture import PotionFixture

f=PotionFixture(7)
f.seed({501:40,505:5})
r=f.refresh()
expected=f.stock()
for preset,threshold in [('protect',65),('conserve',35),('assist',50),('custom',50)]:
    api(f.c,f'preset {f.pid} {preset}')
    assert f'HP <{threshold}%' in f.command('inspect')[1]
    boundary=(r['max_hp']*threshold+99)//100
    f.set('Hp',boundary)
    f.command('follow')
    time.sleep(2.5)
    assert f.stock()==expected, (preset,'drank above boundary')
    f.set('Hp',boundary-1)
    assert f.next_use(expected)==501
    expected[501]-=1
    f.command('stop')
    assert f.stock()==expected
    print('PASS',preset,threshold,'boundary')

f.set('Hp',1)
f.set('Sp',1)
time.sleep(2.6)
assert f.stock()==expected
f.command('follow')
assert f.next_use(expected)==501
first=time.monotonic()
expected[501]-=1
f.set('Hp',r['max_hp'])
assert f.next_use(expected)==505
interval=time.monotonic()-first
assert interval>=1.96, interval  # DB sampling every 25 ms
expected[505]-=1
f.command('stop')
assert f.stock()==expected
print('PASS Stop and shared HP/SP cooldown, seconds',round(interval,3))
f.c.close()
