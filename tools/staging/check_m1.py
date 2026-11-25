"""Real wire-protocol lifecycle test. Run only inside the isolated staging container."""
import pathlib,time,struct,json,sqlite3,os,socket
from protocol import login
root=pathlib.Path('/stage')
assert (root/'STAGING_ONLY').is_file()
results={}; ids=[]
def text(c,needle):
 deadline=time.monotonic()+15
 while time.monotonic()<deadline:
  try:ident,b=c.packet()
  except socket.timeout:continue
  if ident==0x8e and needle.encode() in b:return
 raise AssertionError(needle)
def spawn(c):
 c.command('@companion add knight'); actor=None;feedback=False
 deadline=time.monotonic()+15
 while time.monotonic()<deadline:
  ident,b=c.packet()
  if ident in (0x9fe,0x9ff):
   aid=struct.unpack_from('<I',b,5)[0]
   if 95000000<=aid<100000000:
    assert struct.unpack_from('<H',b,23)[0]==7
    assert struct.unpack_from('<I',b,9)[0]==aid
    actor=aid
  if ident==0x8e and b'Knight companion spawned' in b:feedback=True
  if actor and feedback:
   assert actor not in ids;ids.append(actor)
   if (root/'M4_TEST').exists():
    c.command('@companion skills off');text(c,'Companion skills disabled.')
   return actor
 raise AssertionError('spawn packet missing')
def dismiss(c,aid):
 c.command('@companion dismiss');clear=False;feedback=False
 deadline=time.monotonic()+15
 while time.monotonic()<deadline:
  ident,b=c.packet()
  if ident==0x80 and struct.unpack_from('<I',b,2)[0]==aid:clear=True
  if ident==0x8e and b'Companion dismissed' in b:feedback=True
  if clear and feedback:return
 raise AssertionError('normal clearunit packet missing')
def logs():return (root/'artifacts/map-server.log').read_text(errors='replace')
def detached(aid):
 deadline=time.monotonic()+15
 while time.monotonic()<deadline:
  if f'released id={aid} detached=1 timers_clear=1 active=0' in logs():return
  time.sleep(.1)
 raise AssertionError(f'{aid} not cleaned')
def socket_count():
 # Socket descriptors owned by the map-server, not by the test client.
 for p in pathlib.Path('/proc').iterdir():
  if p.name.isdigit():
   try:
    if (p/'comm').read_text().strip()=='map-server':
     return sum(os.readlink(fd).startswith('socket:') for fd in (p/'fd').iterdir())
   except (FileNotFoundError,PermissionError):pass
 raise AssertionError('map process not found')
c=login()
c.command('@setbattleflag companion_enable 0');text(c,'as requested')
c.command('@companion add knight');text(c,'disabled');results['feature_off']=True
c.command('@where StageOwner');text(c,'prontera');results['normal_command_after_login']=True
c.command('@setbattleflag companion_enable 1');text(c,'as requested')
c.command('@companion add alchemist');text(c,'Usage:');results['invalid_class_rejected']=True
sockets=socket_count()
for n in range(100):
 aid=spawn(c)
 assert socket_count()==sockets
 if (root/'M3_TEST').exists() and n>0:
  from check_m3_combat import joined
  joined(c,aid)
 if n==0:
  if (root/'M2_TEST').exists():
   from check_m2_movement import verify_movement
   results.update(verify_movement(c,aid,text))
  if (root/'M3_TEST').exists():
   from check_m3_combat import verify_combat
   results.update(verify_combat(c,aid,text))
   from check_m3_combat import verify_multiplayer
   results.update(verify_multiplayer(c,aid))
  time.sleep(12) # Exercise natural-regeneration and online-count timers with a live shell.
  if not (root/'M4_TEST').exists():
   c.command('@companion add knight');text(c,'one companion per owner')
  c.command('@setbattleflag companion_enable 0');text(c,'as requested')
 dismiss(c,aid);detached(aid)
 assert socket_count()==sockets
 if n==0:c.command('@setbattleflag companion_enable 1');text(c,'as requested')
 if (n+1)%20==0:print(f'CYCLES {n+1}/100 PASS',flush=True)
results.update(cycles=100,unique_ids=len(ids),standard_spawn_and_clear_packets=True,socket_count_unchanged=True,duplicate_rejected=not (root/'M4_TEST').exists(),dismiss_when_disabled=True)
if (root/'M3_TEST').exists():
 from check_m3_combat import verify_edges
 results.update(verify_edges(c,spawn,dismiss,detached,text))
if (root/'M4_TEST').exists():
 from check_m4_skills import verify_skills
 results.update(verify_skills(c,text))
 from check_m4_exp import verify_exp
 results.update(verify_exp(c,text))
if (root/'M5_TEST').exists():
 from check_m5_recovery import verify_recovery,verify_skill_target
 results.update(verify_recovery(c,text))
 results.update(verify_skill_target(c,text))
if (root/'M6_TEST').exists():
 from check_m6_profiles import verify_profiles,api
 c,extra=verify_profiles(c,text);results.update(extra)
if (root/'M7_TEST').exists():
 from check_m7_policy import verify_policy
 c,extra=verify_policy(c,text);results.update(extra)
if (root/'M8_TEST').exists():
 from check_m8_gear import verify_gear
 c,extra=verify_gear(c,text);results.update(extra)
aid=spawn(c)
if (root/'M3_TEST').exists():joined(c,aid)
if (root/'M5_TEST').exists():
 from check_m4_skills import state
 c.command(f'#kill Companion{aid}');time.sleep(.5)
 assert state(c,aid)['hp']==0
 results['dead_actor_owner_logout']=True
c.close();detached(aid);results['owner_logout_cleanup']=True
# Fresh player login proves teardown did not corrupt the real account/session.
time.sleep(5);c=login();aid=spawn(c)
if (root/'M3_TEST').exists():joined(c,aid)
if (root/'M5_TEST').exists():
 c.command(f'#kill Companion{aid}');time.sleep(.5)
 assert state(c,aid)['hp']==0
 results['dead_actor_shutdown']=True
if (root/'M6_TEST').exists():
 rows,_,_=api(c,f"summon {results['persistent_shutdown_profile']}")
 profile=next(r for r in rows if r['id']==results['persistent_shutdown_profile'])
 c.command(f"#set {profile['name']} BaseExp 789")
if (root/'M8_TEST').exists():
 api(c,f"summon {results['gear_shutdown_profile']}")
# Keep the real owner socket alive for a separate shutdown test by waiting in a background process.
(root/'artifacts/shutdown-ready').write_text(str(aid))
results['shutdown_pending_actor']=aid
results['all_spawned_socketless']=all(f'spawned id={i} owner=2000001:150001 fd=-1 party=0' in logs() for i in ids)
assert results['all_spawned_socketless']
db=sqlite3.connect('file:/stage/ragoff-stage.sqlite3?mode=ro',uri=True)
for table,key in [('login','account_id'),('char','char_id'),('inventory','char_id'),('char_reg_num','char_id'),('char_reg_str','char_id')]:
 assert db.execute(f'SELECT count(*) FROM "{table}" WHERE {key}>=95000000 AND {key}<100000000').fetchone()[0]==0,table
db.close();results['no_synthetic_db_rows']=True
(root/'artifacts/lifecycle-results.json').write_text(json.dumps(results,indent=2))
print('LIFECYCLE_PASS; ready for external graceful shutdown with live owner + companion',flush=True)
try:
 while True:
  try:c.packet()
  except socket.timeout:continue
except (EOFError,ConnectionError,OSError):pass
c.close()
