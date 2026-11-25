"""Exercise the real inventory save barrier, UI detail frames and AI on an isolated M9 fixture."""
import time
from check_m4_skills import wait
from potion_ai_fixture import PotionFixture

f = PotionFixture(7)
c = f.c
syrups = (11621, 11622, 11623, 11624)
potions = (501, 502, 503, 504, 505, 569)
seq = 0

def request(action, modern=True, replay=False):
    global seq
    if not replay:
        seq += 1
    caps = ('ui2 skills7 gear3' if modern else 'ui2 skills4 gear2') if action.startswith('inspect ') else 'ui2'
    if modern and action.startswith('inspect '):
        caps += ' syrup1'
    c.command(f'@companion ui {seq} {action} {caps} hunt1')
    frames = []
    while True:
        code, packet = c.packet()
        if code != 0x8e:
            continue
        parts = packet[4:].rstrip(b'\0').decode().split()
        if parts[:2] == ['[RCO1]', str(seq)]:
            frames.append(parts[2:])
            if parts[2] == 'end':
                return frames

def details(modern=True):
    frames = request(f'inspect {f.pid}', modern)
    stock = {int(t[1]):int(t[2]) for t in frames if t[0]=='supply'}
    bag = {int(t[2]):(int(t[1]),int(t[3])) for t in frames if t[0]=='supplybag'}
    header = next(t for t in frames if t[0]=='detailbegin')
    assert len(stock)==int(header[4]) and len(bag)==int(header[5])
    return stock,bag

def transfer(item, count, giving):
    stock,bag = details()
    before = bag.get(item,(0,0))[1] + stock.get(item,0)
    slot,expected = bag[item] if giving else (0,0)
    verb = 'supplygive' if giving else 'supplytake'
    action = f'{verb} {f.pid} {slot}:{item}:{expected}:{count}'
    assert 'Waiting for inventory' in ' '.join(request(action)[-1])
    wait(c, lambda code,p: code==0x8e and (b'Supplies given.' if giving else b'Supplies returned.') in p)
    assert 'already handled' in ' '.join(request(action,replay=True)[-1])
    after,bag = details()
    bag_amount = bag.get(item,(0,0))[1]
    assert after.get(item,0)==stock.get(item,0)+(count if giving else -count)
    assert bag_amount + after.get(item,0)==before
    end = time.monotonic()+5
    while f.db.execute('select count(*) from ragoff_companion_supply_journal').fetchone()[0]:
        assert time.monotonic()<end
        time.sleep(.05)
    saved = f.db.execute('select coalesce(sum(amount),0) from inventory where char_id=? and nameid=?',(f.owner,item)).fetchone()[0]
    assert saved==bag_amount and f.stock().get(item,0)==after.get(item,0)

def consume(item, hp, sp):
    before = f.stock()
    f.set('Hp',hp)
    f.set('Sp',sp)
    f.command('follow')
    assert f.next_use(before)==item
    f.command('stop')
    before[item]-=1
    assert f.stock()==before
    row=f.refresh()
    assert (row['sp']>sp if item in (505,533,11624) else row['hp']>hp)
    print('PASS consumed exactly one and recovered',item)

assert 'reserve' in f.command('bench')[1].lower()
for item in syrups:
    c.command(f'@item {item} 8')
time.sleep(.5)
f.seed({item:2 for item in potions})
initial = {item:details()[1][item][1] for item in syrups}
for item in syrups:
    transfer(item,5,True)
    transfer(item,1,False)
assert len(details()[0])==10
legacy,legacy_bag=details(False)
assert set(legacy)==set(potions) and not set(syrups).intersection(legacy_bag)
print('PASS four give/return cycles, replay, persisted inventory, ten modern and six legacy stock rows')
stock_before,bag_before=details()
slot,expected=bag_before[11624]
f.db.execute("CREATE TRIGGER syrup_write_failure BEFORE UPDATE ON ragoff_companion_supply BEGIN SELECT RAISE(FAIL,'fixture injection'); END")
try:
    assert 'Waiting' in ' '.join(request(f'supplygive {f.pid} {slot}:11624:{expected}:1')[-1])
    wait(c,lambda code,p: code==0x8e and b'Supply transfer failed' in p)
    assert details()==(stock_before,bag_before)
    assert f.db.execute('select count(*) from ragoff_companion_supply_journal').fetchone()==(0,)
finally:
    f.db.execute('DROP TRIGGER syrup_write_failure')
print('PASS failed stock write rolls back inventory and journal')
c.command('@set BaseLevel 59')
time.sleep(.8)
f.command('summon')
f.command('stop')
r=f.refresh()
consume(504,1,r['max_sp'])
c.command('@set BaseLevel 60')
time.sleep(1)
r=f.refresh()
request(f'preset {f.pid} protect')
# At this Knight's level and VIT, Yellow Syrup is closest to the half-HP deficit.
# Both White Syrup and the smaller ordinary potions are available.
consume(11622,r['max_hp']//2,r['max_sp'])
consume(11623,1,r['max_sp'])
consume(11624,r['max_hp'],1)
consume(505,r['max_hp'],1)  # Blue Syrup still has its native 10-second delay.
f.command('bench')
used = {11622:1,11623:1,11624:1}
for item in (11623,11622,11621):
    if item!=11623:
        f.command('summon')
        f.command('stop')
        r=f.refresh()
        # Remove old HP potions for the Red Syrup trial (White Potion is stronger).
        consume(item,1,r['max_sp'])
        used[item]=used.get(item,0)+1
        f.command('bench')
    transfer(item,details()[0][item],False)
    if item==11622:
        for potion in (501,502,503,504,569):
            transfer(potion,details()[0][potion],False)
transfer(11624,details()[0][11624],False)
stock,bag=details()
assert all(item not in stock and bag[item][1]+used[item]==initial[item] for item in syrups)
print('PASS final owner inventory + consumed = initial for every Syrup', initial, used)
# Exercise one food at a time through the actual deposit/use/return path.
for old,count in list(details()[0].items()):
    transfer(old,count,False)
for food in (517,518,533):
    c.command(f'@item {food} 4')
    time.sleep(.3)
    transfer(food,3,True)
    assert food not in details(False)[0]
    f.command('summon')
    f.command('stop')
    r=f.refresh()
    consume(food,1 if food!=533 else r['max_hp'],1 if food!=517 else r['max_sp'])
    f.command('bench')
    transfer(food,2,False)
    assert details()[1][food][1]==3
print('PASS Meat, Honey and Grape Juice, give/return and native HP/SP recovery')
c.close()
