"""Exercise native equip stats and physical instance conservation on a disposable server."""
import itertools
import sys
import re
import sqlite3
from pathlib import Path
from check_m6_profiles import api
from check_m8_gear import transfer, returned, conserved
from protocol import login

root = Path('/stage')
assert (root / 'STAGING_ONLY').exists()
db = sqlite3.connect(root / 'ragoff-stage.sqlite3')
cases = [(644249399999992, 7, 4003), (644249399999993, 4, 0), (644249399999994, 0, 4003)]
db.executemany('INSERT INTO inventory(char_id,nameid,unique_id,amount,identify,refine,card0) VALUES(150001,2302,?,1,1,?,?)', cases)
db.execute('UPDATE ragoff_companion SET hp=g.max_hp,sp=g.max_sp FROM ragoff_companion_growth g WHERE g.profile_id=ragoff_companion.id')
db.commit()
fields = [row[1] for row in db.execute('pragma table_info(inventory)') if row[1] != 'id']
def inventory(uid):
    return db.execute('SELECT '+','.join(fields)+' FROM inventory WHERE unique_id=?', (uid,)).fetchall()
before = {uid: inventory(uid) for uid, _, _ in cases}
assert all(len(rows) == 1 for rows in before.values())
c = login()
c.command('@setbattleflag companion_enable 1')
pid = next(r['id'] for r in api(c, 'list')[0] if r['job'] == 7)
seq = itertools.count(10001)
def inspect():
    n = next(seq)
    c.command(f'@companion ui {n} inspect {pid} ui2 skills4 gear2')
    frames = []
    while True:
        i,b = c.packet()
        if i != 0x8e: continue
        f = b[4:].rstrip(b'\0').decode().split()
        if f[:2] != ['[RCO1]',str(n)]: continue
        if f[2] == 'end': return frames
        frames.append(f[2:])
def stats():
    hp = next(r['max_hp'] for r in api(c,'list')[0] if r['id'] == pid)
    note = api(c,f'gear {pid}')[1]
    return hp,int(re.search(r'defense=(\d+)',note)[1])
for uid, refine, card in cases:
    bag = next(f for f in inspect() if f[0]=='bag' and f[3]==str(uid))
    assert bag[4:] == [str(refine),str(card),'0','0','0']
    if sys.argv[1:] == ['old-char']:
        from check_m4_skills import wait
        assert 'Waiting for inventory' in api(c,f'give {pid} {bag[1]}')[1]
        wait(c,lambda i,b:i==0x8e and b'does not support modified equipment' in b)
        conserved(uid)
        assert inventory(uid) == before[uid]
        print('PASS older Char Server kept the original item',uid)
        continue
    transfer(c,pid,int(bag[1]))
    assert not inventory(uid)
    conserved(uid)
    gear = next(f for f in inspect() if f[0]=='gear' and f[2]=='2302')
    assert gear[5:] == bag[4:]
    gid = int(gear[1])
    assert 'Summoned' in api(c,f'summon {pid}')[1]
    api(c,f'stop {pid}')
    hp, defense = stats()
    note = api(c,f'equip {pid} {gid}')[1]
    assert 'equipped and saved' in note, note
    equipped_hp, equipped_def = stats()
    assert equipped_hp == hp + (700 if card else 0) and (equipped_def > defense if refine else equipped_def == defense), (hp,defense,equipped_hp,equipped_def)
    api(c,f'bench {pid}')
    api(c,f'summon {pid}')
    assert stats() == (equipped_hp,equipped_def)
    api(c,f'bench {pid}')
    transfer(c,pid,gid,False)
    returned(uid)
    assert inventory(uid) == before[uid]
    assert db.execute('select count(*) from ragoff_companion_gear_details where gear_id=?',(gid,)).fetchone()==(0,)
    print('PASS refine',refine,'card',card,'identical inventory fields, UID and count; HP',hp,'->',equipped_hp,'DEF',defense,'->',equipped_def)
c.close()
