"""Resource rollback, metadata guard, pending logout and durability after native use."""
import pathlib,json,time
from protocol import login
from check_m6_profiles import api
from check_m8_gear import query,trigger,pause_char
R=pathlib.Path('/stage');assert (R/'M9_TEST').exists()
def stocks(pid):return query('SELECT nameid,amount FROM ragoff_companion_supply WHERE profile_id=? ORDER BY nameid',(pid,))
def inventory():return query('SELECT nameid,amount FROM inventory WHERE char_id=150001 ORDER BY id')
c=login();c.command('@setbattleflag natural_healhp_interval 3600000');c.command('@setbattleflag natural_healsp_interval 3600000')
kid=next(r['id'] for r in api(c,'list')[0] if r['job']==7)
r=next(r for r in api(c,f'summon {kid}')[0] if r['id']==kid);api(c,f'stop {kid}')
c.command(f'#set {r["name"]} Hp 1');c.command(f'#set {r["name"]} Sp 1');time.sleep(.3)
old=stocks(kid)
trigger("CREATE TRIGGER m93_fail_resource BEFORE UPDATE OF hp ON ragoff_companion BEGIN SELECT RAISE(FAIL,'M93 resource commit failure'); END")
api(c,f'follow {kid}');time.sleep(3);api(c,f'stop {kid}');r=next(r for r in api(c,'list')[0] if r['id']==kid)
assert (r['hp'],r['sp'])==(1,1),r
assert stocks(kid)==old
trigger('DROP TRIGGER m93_fail_resource');api(c,f'bench {kid}')
# Snapshot after successful consumption is durable across reserve/summon.
r=next(r for r in api(c,f'summon {kid}')[0] if r['id']==kid);api(c,f'stop {kid}');assert (r['hp'],r['sp'])==(1,1)
api(c,f'follow {kid}');time.sleep(2.5);api(c,f'stop {kid}');r=next(r for r in api(c,'list')[0] if r['id']==kid);assert r['hp']>1
saved=stocks(kid);api(c,f'bench {kid}');r2=next(r for r in api(c,f'summon {kid}')[0] if r['id']==kid);api(c,f'stop {kid}');assert (r2['hp'],r2['sp'])==(r['hp'],r['sp']) and stocks(kid)==saved;api(c,f'bench {kid}')
# Dead companions cannot spend supplies or heal themselves.
r=next(r for r in api(c,f'summon {kid}')[0] if r['id']==kid);c.command('#kill '+r['name']);time.sleep(.2);old_dead=stocks(kid);time.sleep(2.5);assert stocks(kid)==old_dead
assert next(r for r in api(c,'list')[0] if r['id']==kid)['hp']==0;api(c,f'bench {kid}')
# Pending owner logout cancels the late barrier. Inventory and supplies remain unchanged.
# Read player slot from opt-in inspect frames (the API already validates ownership).
frames=[];orig=c.packet
def packet():
 i,b=orig()
 if i==0x8e and b'supplybag' in b:frames.append(b[4:].decode().strip('\0').split())
 return i,b
c.packet=packet;api(c,f'inspect {kid}');c.packet=orig
v=next(x for x in frames if x[4]=='501');old=stocks(kid);inv=inventory();pause_char(True)
try:
 assert 'Waiting' in api(c,f'supplygive {kid} {v[3]}:501:{v[5]}:1')[1];c.close();time.sleep(1)
finally:pause_char(False)
time.sleep(1);assert stocks(kid)==old and inventory()==inv
c=login();assert not query('SELECT * FROM ragoff_companion_supply_journal');c.close()
result=dict(resource_commit_failure_rolls_back_stock_and_hp_sp=True,reserve_summon_preserves_resources_and_potions=True,pending_owner_logout_no_transfer=True,dead_companion_does_not_use_potions=True)
(R/'artifacts/m93-fault-results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
