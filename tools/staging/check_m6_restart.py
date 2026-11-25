#!/usr/bin/env python3
"""Disposable m6 runtime only: graceful restart and forced map crash persistence."""
import pathlib,subprocess,json,time,sys
root=pathlib.Path(__file__).resolve().parents[2];mode=sys.argv[1] if len(sys.argv)>1 else 'm6';assert mode in ('m6','m7','m8');stage=root/('runtime/'+mode);name='ragoff-companion-'+mode
assert (stage/'M6_TEST').exists()
result=json.loads((stage/'artifacts/lifecycle-results.json').read_text());pid=result['persistent_shutdown_profile']
assert result['persistent_shutdown_save']
info=json.loads(subprocess.check_output(['docker','inspect',name]))[0]
assert info['HostConfig']['NetworkMode']=='none' and not info['State']['Running']
def restart(label):
 (stage/'artifacts').rename(stage/label);(stage/'artifacts').mkdir()
 subprocess.run(['docker','start',name],check=True)
 for _ in range(180):
  p=stage/'artifacts/map-server.log'
  if p.exists() and 'Map Server is now online.' in p.read_text(errors='replace'):return
  time.sleep(1)
 raise RuntimeError('restart readiness timeout')
def client(expected,crash):
 code=f'''import sys,time,os,signal,json
sys.path.insert(0,'/tests')
from protocol import login
from check_m6_profiles import api,read_db
c=login(); c.command('@setbattleflag companion_enable 1'); rows,_,_=api(c,'list');p=next(r for r in rows if r['id']=={pid})
assert p['actor']==0 and p['exp']=={expected},p
rows,_,_=api(c,'summon {pid}');p=next(r for r in rows if r['id']=={pid});assert p['actor']>0
'''
 if mode in ('m7','m8'): code+=f"assert 'skills=heal,resurrection' in api(c,'config {pid}')[1]\n"
 if mode=='m8':
  gearpid=result['gear_shutdown_profile'];uid=result['gear_shutdown_unique']
  code+=f"\nimport sqlite3\ndb=sqlite3.connect('file:/stage/ragoff-stage.sqlite3?mode=ro',uri=True)\nassert db.execute('SELECT count(*) FROM ragoff_companion_gear WHERE unique_id=? AND state=0 AND equip>0',('{uid}',)).fetchone()[0]==1\nassert db.execute('SELECT count(*) FROM inventory WHERE unique_id=?',('{uid}',)).fetchone()[0]==0\ndb.close()\nrows,_,_=api(c,'summon {gearpid}');assert next(r for r in rows if r['id']=={gearpid})['actor']>0\nassert 'weapon_atk=25' in api(c,'gear {gearpid}')[1]\napi(c,'bench {gearpid}')\n"
 if crash:
  code+='''c.command('#set '+p['name']+' BaseExp 234');time.sleep(6)
assert next(r for r in read_db() if r['id']==p['id'])['base_exp']=='234'
from pathlib import Path
for d in Path('/proc').iterdir():
 if d.name.isdigit():
  try: cmd=(d/'cmdline').read_bytes().split(b'\\0')[0]
  except OSError:continue
  if cmd.endswith(b'map-server'):os.kill(int(d.name),signal.SIGKILL);break
else:raise AssertionError('map process missing')
print('checkpoint-before-crash PASS',flush=True)
'''
 else: code+="api(c,'bench '+str(p['id']));c.close();print('restart-resummon PASS',flush=True)"
 subprocess.run(['docker','exec',name,'python3','-c',code],check=True)
restart('artifacts-final-lifecycle')
client(789,True)
subprocess.run(['docker','wait',name],check=True,timeout=60)
restart('artifacts-forced-crash')
client(234,False)
subprocess.run(['docker','stop','-t','35',name],check=True)
assert (stage/'artifacts/exit-codes.txt').read_text()=='[0, 0, 0]'
receipt={'graceful_restart_profile_preserved':True,'forced_map_crash_checkpoint_preserved':True,'no_automatic_actor_resummon':True,'resummon_after_restart':True,'profile_id':pid,'maximum_checkpoint_loss_seconds_approx':5}
if mode=='m8':receipt.update(gear_unique_instance_preserved=True,gear_native_stats_restored_after_crash=True)
(root/f'audit/evidence/{mode}-restart-crash.json').write_text(json.dumps(receipt,indent=2))
# Restore full lifecycle artifacts at canonical verification path.
(stage/'artifacts').rename(stage/'artifacts-restart-success');(stage/'artifacts-final-lifecycle').rename(stage/'artifacts')
print(json.dumps(receipt))
