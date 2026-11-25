"""Equipment escrow through real owner commands/native inventory and equip paths."""
import pathlib,sqlite3,time,re,os,signal
from protocol import login
from check_m6_profiles import api
from check_m4_skills import wait
ROOT=pathlib.Path('/stage');assert (ROOT/'M8_TEST').exists()
def query(sql,args=()):
 db=sqlite3.connect('file:/stage/ragoff-stage.sqlite3?mode=ro',uri=True);r=db.execute(sql,args).fetchall();db.close();return r

def slot(c,item=1101):
 c.command('@companion inventory');b=wait(c,lambda i,b:i==0x8e and b'Inventory slot ' in b and f'({item})'.encode() in b)
 return int(re.search(rb'slot (\d+)',b)[1])
def transfer(c,pid,selection,give=True,success=True):
 _,note,_=api(c,f'{"give" if give else "take"} {pid} {selection}');assert 'Waiting for inventory' in note,note
 b=wait(c,lambda i,b:i==0x8e and any(t in b for t in (b'Equipment given.',b'Equipment returned',b'Give failed',b'Return failed',b'Inventory full',b'transfer cancelled')))
 msg=b[4:].decode(errors='replace')
 assert (('Equipment given.' in msg or 'Equipment returned' in msg)==success),msg
 return msg

def held(pid):return query('SELECT id,unique_id,equip,state FROM ragoff_companion_gear WHERE profile_id=? ORDER BY id',(pid,))
def conserved(uid):
 n=query('SELECT count(*) FROM inventory WHERE unique_id=?',(uid,))[0][0]+query('SELECT count(*) FROM ragoff_companion_gear WHERE unique_id=? AND state=0',(str(uid),))[0][0]
 assert n==1,(uid,n)
def returned(uid):
 end=time.monotonic()+5
 while query('SELECT count(*) FROM ragoff_companion_gear WHERE unique_id=?',(str(uid),))[0][0]:
  assert time.monotonic()<end,'return journal not acknowledged';time.sleep(.05)
 conserved(uid)
def pause_char(stop):
 for p in pathlib.Path('/proc').iterdir():
  if p.name.isdigit():
   try:a=(p/'cmdline').read_bytes().split(b'\0')[0]
   except OSError:continue
   if a.endswith(b'char-server'):os.kill(int(p.name),signal.SIGSTOP if stop else signal.SIGCONT);return
 raise AssertionError('Char test process missing')
def trigger(sql):
 db=sqlite3.connect(ROOT/'ragoff-stage.sqlite3');db.execute(sql);db.commit();db.close()
def verify_gear(c,text):
 rows,_,_=api(c,'list');kid=next(r['id'] for r in rows if r['job']==7);pid=next(r['id'] for r in rows if r['job']==8)
 c.command('@heal');c.command('@item 1101 1');s=slot(c)
 transfer(c,kid,s);gid,uid,_,_=held(kid)[0];conserved(uid)
 assert 'Return all' in api(c,f'retire {kid} confirm')[1]
 peer=login('/stage/peer-fixture.json');assert 'not found' in api(peer,f'take {kid} {gid}')[1];peer.close()
 rows,_,_=api(c,f'summon {kid}');assert 'Reserve' in api(c,f'take {kid} {gid}')[1]
 assert 'Stop' in api(c,f'equip {kid} {gid}')[1];api(c,f'stop {kid}')
 before=int(re.search(r'weapon_atk=(\d+)',api(c,f'gear {kid}')[1])[1])
 assert 'equipped and saved' in api(c,f'equip {kid} {gid}')[1]
 after=int(re.search(r'weapon_atk=(\d+)',api(c,f'gear {kid}')[1])[1]);assert after>before,(before,after)
 assert held(kid)[0][2]!=0
 trigger("CREATE TRIGGER m8_fail_equip BEFORE UPDATE OF equip ON ragoff_companion_gear BEGIN SELECT RAISE(FAIL,'M8 injected equip failure'); END")
 assert 'save failed' in api(c,f'unequip {kid} {gid}')[1]
 assert 'Summon failed' in api(c,f'summon {kid}')[1]
 trigger('DROP TRIGGER m8_fail_equip')
 assert next(r for r in api(c,'list')[0] if r['id']==kid)['actor']==0
 assert held(kid)[0][2]!=0
 api(c,f'summon {kid}');assert int(re.search(r'weapon_atk=(\d+)',api(c,f'gear {kid}')[1])[1])==after
 api(c,f'stop {kid}');assert 'unequipped and saved' in api(c,f'unequip {kid} {gid}')[1]
 assert int(re.search(r'weapon_atk=(\d+)',api(c,f'gear {kid}')[1])[1])==before
 api(c,f'equip {kid} {gid}');api(c,f'bench {kid}')
 trigger("CREATE TRIGGER m8_fail_take BEFORE UPDATE OF state ON ragoff_companion_gear BEGIN SELECT RAISE(FAIL,'M8 injected return failure'); END")
 transfer(c,kid,gid,False,False);conserved(uid);trigger('DROP TRIGGER m8_fail_take')
 transfer(c,kid,gid,False);returned(uid)
 # Native Priest job restrictions still apply; no item is deleted on rejection.
 transfer(c,pid,slot(c));pgid=held(pid)[0][0];api(c,f'summon {pid}');api(c,f'stop {pid}')
 assert 'Cannot equip' in api(c,f'equip {pid} {pgid}')[1];assert held(pid)[0][2]==0
 api(c,f'bench {pid}');transfer(c,pid,pgid,False);returned(uid)
 trigger("CREATE TRIGGER m8_fail_give BEFORE INSERT ON ragoff_companion_gear BEGIN SELECT RAISE(FAIL,'M8 injected give failure'); END")
 transfer(c,kid,slot(c),True,False);conserved(uid);trigger('DROP TRIGGER m8_fail_give')
 # Repeated transfers retain the same physical instance identity exactly once.
 for n in range(100):
  transfer(c,kid,slot(c));gid=held(kid)[0][0];conserved(uid)
  assert 'Only unequipped' in api(c,f'give {kid} 1')[1]
  transfer(c,kid,gid,False);returned(uid)
 print('GEAR_TRANSFER_CYCLES_100_PASS',flush=True)
 # Full/overweight inventory cannot consume a stored item.
 transfer(c,kid,slot(c));gid=held(kid)[0][0];c.command('@item 2601 100')
 assert 'Inventory full' in transfer(c,kid,gid,False,False);conserved(uid)
 c.command('@itemreset');transfer(c,kid,gid,False);returned(uid)
 # Force a barrier timeout: delayed ACK must not perform the timed-out action.
 s=slot(c);pause_char(True)
 try:
  assert 'Waiting' in api(c,f'give {kid} {s}')[1]
  text(c,'Equipment transfer timed out')
 finally:pause_char(False)
 time.sleep(.5);assert not held(kid);conserved(uid)
 # Logout with no actors must cancel the pending operation and its timer.
 pause_char(True)
 try:
  assert 'Waiting' in api(c,f'give {kid} {s}')[1];c.close();time.sleep(1)
 finally:pause_char(False)
 time.sleep(5);c=login();assert not held(kid);conserved(uid)
 # Changing the selected instance during the save wait cancels the operation.
 s=slot(c);pause_char(True)
 try:
  api(c,f'give {kid} {s}');c.command('@itemreset');c.command('@item 1101 1');time.sleep(.3)
 finally:pause_char(False)
 text(c,'Inventory changed; no item moved.');assert not held(kid)
 # Leave a correctly equipped item for shutdown/restart/crash recovery checks.
 transfer(c,kid,slot(c));gid,uid,_,_=held(kid)[0]
 api(c,f'summon {kid}');api(c,f'stop {kid}');assert 'equipped and saved' in api(c,f'equip {kid} {gid}')[1];api(c,f'bench {kid}');conserved(uid)
 return c,dict(gear_transfer_cycles=100,gear_native_equipment_stats=True,gear_native_job_restrictions=True,gear_ownership_and_release_guard=True,gear_sql_failure_atomic=True,gear_equipment_save_failure_restores=True,gear_full_inventory_return_guard=True,gear_barrier_timeout_no_mutation=True,gear_pending_owner_logout_cleanup=True,gear_changed_instance_cancelled=True,gear_shutdown_profile=kid,gear_shutdown_id=gid,gear_shutdown_unique=str(uid),gear_weapon_atk=after)
