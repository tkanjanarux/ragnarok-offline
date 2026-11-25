"""Native wire supplies conservation and companion detail frames. Disposable fixtures only."""
import pathlib,json,time,sqlite3,re,socket
from protocol import login
from check_m6_profiles import api
from check_m4_skills import wait
from check_m4_exp import warp
from check_m8_gear import query,pause_char,trigger
R=pathlib.Path('/stage');assert (R/'M9_TEST').exists()
def own(id):return query('SELECT COALESCE(SUM(amount),0) FROM inventory WHERE char_id=150001 AND nameid=?',(id,))[0][0]
def stock(pid,id):return query('SELECT COALESCE((SELECT amount FROM ragoff_companion_supply WHERE profile_id=? AND nameid=?),0)',(pid,id))[0][0]
def inspect(c,pid):
 frames=[];orig=c.packet
 def packet():
  i,b=orig()
  if i==0x8e and b'[RCO1]' in b:frames.append(b[4:].decode().rstrip('\0'))
  return i,b
 c.packet=packet
 try:rows,note,on=api(c,f'inspect {pid}')
 finally:c.packet=orig
 (R/'artifacts/m93-frames.json').write_text(json.dumps(frames))
 return rows,note,frames

def bag(c,pid,id):
 for f in inspect(c,pid)[2]:
  t=f.split()
  if len(t)==6 and t[2]=='supplybag' and int(t[4])==id:return int(t[3]),int(t[5])
 raise AssertionError('missing supply bag '+str(id))
def transfer(c,pid,id,n,give=True,success=True):
 slot,expected=bag(c,pid,id) if give else (0,0)
 note=api(c,f'{"supplygive" if give else "supplytake"} {pid} {slot}:{id}:{expected}:{n}')[1]
 assert 'Waiting for inventory' in note,note
 b=wait(c,lambda i,b:i==0x8e and any(x in b for x in (b'Supplies given.',b'Supplies returned.',b'Supply transfer failed',b'Inventory full',b'transfer cancelled',b'Inventory changed')))
 msg=b[4:].decode(errors='replace');assert (('Supplies given.' in msg or 'Supplies returned.' in msg)==success),msg
 end=time.monotonic()+5
 while query('SELECT count(*) FROM ragoff_companion_supply_journal')[0][0]:
  assert time.monotonic()<end,'journal not acknowledged';time.sleep(.05)
 return msg
c=login();c.command('@setbattleflag companion_enable 1');c.command('@jobchange 4054');c.command('@allskill');c.command('@set BaseLevel 30');c.command('@set JobLevel 29');c.command('@setbattleflag natural_healhp_interval 3600000');c.command('@setbattleflag natural_healsp_interval 3600000');warp(c,'prontera 150 180');api(c,'party')
for j in ('knight','priest','wizard'):api(c,'recruit '+j)
rows=api(c,'list')[0];kid=next(r['id'] for r in rows if r['job']==7);pid=next(r['id'] for r in rows if r['job']==8)
for id in (501,505):c.command(f'@item {id} 100')
time.sleep(.3)
frames=inspect(c,kid)[2];assert sum(' starter ' in f for f in frames)==2 and sum(' skill ' in f for f in frames)==2
transfer(c,kid,501,20);transfer(c,kid,505,20)
assert own(501)==own(505)==80 and stock(kid,501)==stock(kid,505)==20
peer=login('/stage/peer-fixture.json');assert 'not found' in api(peer,f'supplytake {kid} 0:501:0:1')[1];peer.close()
# Both directions preserve stack totals and do not duplicate during repeated saves.
for _ in range(100):
 transfer(c,kid,501,1);assert own(501)+stock(kid,501)==100
 transfer(c,kid,501,1,False);assert own(501)+stock(kid,501)==100
print('SUPPLY_TRANSFER_100_PASS',flush=True)
# Native use consumes real stock; Stop suspends it even with very low resources.
r=next(r for r in api(c,f'summon {kid}')[0] if r['id']==kid);api(c,f'stop {kid}')
c.command(f'#set {r["name"]} Hp 1');c.command(f'#set {r["name"]} Sp 1');time.sleep(2.5)
assert stock(kid,501)==stock(kid,505)==20
api(c,f'follow {kid}');end=time.monotonic()+30
while stock(kid,501)==20 or stock(kid,505)==20:
 assert time.monotonic()<end,('potions not consumed',stock(kid,501),stock(kid,505));time.sleep(.2)
api(c,f'stop {kid}');r=next(r for r in api(c,'list')[0] if r['id']==kid);assert r['hp']>1 and r['sp']>1
assert query('SELECT hp,sp FROM ragoff_companion WHERE id=?',(kid,))[0][0]>1
api(c,f'bench {kid}')
# SQL failure must leave player and stock unchanged.
trigger("CREATE TRIGGER m93_fail_give BEFORE UPDATE ON ragoff_companion_supply BEGIN SELECT RAISE(FAIL,'M93 injected failure'); END")
a,b=own(501),stock(kid,501);transfer(c,kid,501,1,success=False);assert (own(501),stock(kid,501))==(a,b);trigger('DROP TRIGGER m93_fail_give')
# Late barrier following timeout cannot move items.
slot,n=bag(c,kid,501);pause_char(True)
try:
 assert 'Waiting' in api(c,f'supplygive {kid} {slot}:501:{n}:1')[1];time.sleep(11)
finally:pause_char(False)
time.sleep(.5);assert (own(501),stock(kid,501))==(a,b)
# One profile cannot borrow another profile's stock.
api(c,f'summon {pid}');api(c,f'stop {pid}');p=next(r for r in api(c,'list')[0] if r['id']==pid)
c.command(f'#set {p["name"]} Sp 1');api(c,f'follow {pid}');time.sleep(2.5);api(c,f'stop {pid}');assert stock(pid,505)==0 and stock(kid,505)<20;api(c,f'bench {pid}')
result=dict(detail_frames=True,transfer_cycles=100,per_profile_stock=True,native_hp_sp_use=True,stop_pauses_potions=True,atomic_sql_failure=True,late_barrier_timeout_no_mutation=True,cross_owner_denied=True)
c.close();(R/'artifacts/m93-results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
