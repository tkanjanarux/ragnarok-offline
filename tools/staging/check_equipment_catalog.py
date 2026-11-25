"""Real escrow across a process restart, native cast gauges, combo and autobonus."""
import json
import re
import sqlite3
import struct
import time
from pathlib import Path
from check_m6_profiles import api
from check_m4_skills import wait
from check_m8_gear import transfer, returned, conserved
from check_m4_exp import warp
from companion_ai_fixture import attack,owner
from protocol import login,entry

stage=Path('/stage')
assert (stage/'STAGING_ONLY').exists()
saved=stage/'artifacts/equipment-restart.json'
db=sqlite3.connect(stage/'ragoff-stage.sqlite3')
cols=[r[1] for r in db.execute('pragma table_info(inventory)') if r[1]!='id']
def snapshot(uid):
    return db.execute('select '+','.join(cols)+' from inventory where unique_id=?',(uid,)).fetchall()
ids=[5354,5355,5286,5502,5401,5653,980007,2302]+[2601]*15
uids=[644249399980000+i for i in range(len(ids))]
if not saved.exists():
    # Deterministic proc chance makes the combat check independent of RNG.
    imp=stage/'db/import/item_db.yml'
    with imp.open('a') as f:
        f.write("""  - Id: 980007
    AegisName: QA_Passive_Ring
    Name: QA Passive Ring
    Type: Armor
    Locations:
      Right_Accessory: true
      Left_Accessory: true
    ArmorLevel: 1
    Script: |
      autobonus "{ bonus bDex,20; }",1000,6000,BF_MAGIC;
""")
    for uid,i in zip(uids,ids):
        db.execute('insert into inventory(char_id,nameid,amount,identify,unique_id) values(150001,?,1,1,?)',(i,uid))
    db.execute('update inventory set refine=7,card0=4003,option_id0=1,option_val0=77,option_id1=2,option_val1=14 where unique_id=?',(uids[7],))
    db.commit()
c=login()
if not saved.exists():
    c.command('@reloaditemdb')
    time.sleep(2)
c.command('@setbattleflag companion_enable 1')
c.command('@jobchange 7')
c.command('@set BaseLevel 81')
c.command('@set JobLevel 36')
c.command('@heal')
warp(c,'prontera 150 180')
pid=next(r['id'] for r in api(c,'list')[0] if r['job']==9)
seq=5000
def inspect():
    global seq
    seq+=1
    c.command(f'@companion ui {seq} inspect {pid} ui2 skills7 gear3 syrup1 hunter1')
    rows=[]
    while True:
        _,b=c.until({0x8e})
        f=b[4:].rstrip(b'\0').decode().split()
        if f[:2]!=['[RCO1]',str(seq)]:continue
        if f[2]=='end':return rows
        rows.append(f[2:])
if not saved.exists():
    before=[snapshot(uid)[0] for uid in uids]
    for uid in uids:
        rows=inspect()
        match=next(r for r in rows if r[0] in ('blocked','bag') and r[3]==str(uid))
        assert match[0]=='bag',match
        transfer(c,pid,int(match[1]))
        conserved(uid)
    saved.write_text(json.dumps(before))
    print('PASS deposited 23 distinct UIDs, four Cash Shop hats and modified armor',flush=True)
    c.close()
    raise SystemExit(0)
before=json.loads(saved.read_text())
for uid in uids:conserved(uid)
gids=[db.execute('select id from ragoff_companion_gear where unique_id=?',(str(u),)).fetchone()[0] for u in uids]
assert len([r for r in inspect() if r[0]=='gear'])==len(uids)
rows,note,_=api(c,f'summon {pid}')
assert 'Summoned' in note,note
actor=next(r['actor'] for r in rows if r['id']==pid)
def equip(i,on=True):
    api(c,f'stop {pid}')
    verb='equip' if on else 'unequip'
    note=api(c,f'{verb} {pid} {gids[i]}')[1]
    assert 'and saved' in note,(ids[i],note)
def status():
    c.command('@companion status')
    p=wait(c,lambda i,b:i==0x8e and f'Companion id={actor} '.encode() in b)
    return {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',p.decode(errors='replace'))}
base=status()
equip(4)
assert status()['total_int']==base['total_int']+1
equip(5)
assert status()['total_int']==base['total_int']+2
equip(5,False)
assert status()['total_int']==base['total_int']+1
equip(4,False)
assert status()['total_int']==base['total_int']
equip(7)
hp=next(r['max_hp'] for r in api(c,'list')[0] if r['id']==pid)
equip(7,False)
plainhp=next(r['max_hp'] for r in api(c,'list')[0] if r['id']==pid)
assert hp-plainhp==777,(hp,plainhp)
api(c,f'skills {pid} none')
script=stage/'npc/custom/qa_equipment_bolt.txt'
script.write_text('-\tscript\tQA Bolt Kit\t-1,{\nOnInit: bindatcmd "kitbolt",strnpcinfo(3)+"::OnBolt",99,99; bindatcmd "kitegg",strnpcinfo(3)+"::OnEgg",99,99; end;\nOnBolt: unitskilluseid atoi(.@atcmd_parameters$[0]),19,5,atoi(.@atcmd_parameters$[1]); end;\nOnEgg: monster "prontera",150,180,"QA",1097,1; setunitdata $@mobid[0],UMOB_MAXHP,500000; setunitdata $@mobid[0],UMOB_HP,500000; end;\n}\n')
c.command('@loadnpc npc/custom/qa_equipment_bolt.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
c.command('@kitegg')
mob=struct.unpack_from('<I',wait(c,lambda i,b:i in (0x9fe,0x9ff) and struct.unpack_from('<H',b,23)[0]==1097),5)[0]
attack(c,mob)
wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(owner,mob) and struct.unpack_from('<i',b,22)[0]>0)
c.send(struct.pack('<H',entry('clif_parse_StopAttack')[0]))
def bolt():
    api(c,f'assist {pid}')
    c.command(f'@kitbolt {actor} {mob}')
    p=wait(c,lambda i,b:i in (0x13e,0x7fb,0xb1a) and struct.unpack_from('<II',b,2)==(actor,mob))
    delay=struct.unpack_from('<I',p,20)[0]
    wait(c,lambda i,b:i==0x1de and struct.unpack_from('<HII',b,2)==(19,actor,mob))
    time.sleep(1)
    return delay
plain=bolt()
delays=[]
for n in range(4):
    equip(n)
    delays.append(bolt())
    equip(n,False)
    assert bolt()==plain
assert delays[0]==delays[1]==delays[2] and delays[3]<delays[2]<plain,(plain,delays)
equip(6)
bolt()
assert status()['total_dex']==base['total_dex']+20
equip(6,False)
assert status()['total_dex']==base['total_dex']
api(c,f'bench {pid}')
for uid,gid,expected in zip(uids,gids,before):
    transfer(c,pid,gid,False)
    returned(uid)
    assert [list(r) for r in snapshot(uid)]==[expected]
print('PASS restart, 23 exact returns, combo INT, +777 card/option HP, native autobonus +20 DEX removed, hat cast times ms',plain,delays)
c.close()
