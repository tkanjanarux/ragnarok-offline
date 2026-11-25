#!/usr/bin/env python3
"""Run lifecycle tests and graceful shutdown against an already-running isolated staging."""
import json,pathlib,subprocess,sys,time,re,hashlib
root=pathlib.Path(__file__).resolve().parents[2]
mode=sys.argv[1];assert mode in ('m1','asan','m2','m2asan','m3','m3asan','m4','m4asan','m5','m5asan','m6','m6asan','m7','m7asan','m8','m8asan','m8probe','m9off')
name='ragoff-companion-'+mode;stage=root/'runtime'/mode;art=stage/'artifacts'
info=json.loads(subprocess.check_output(['docker','inspect',name]))[0]
assert info['HostConfig']['NetworkMode']=='none'
assert not info['HostConfig']['PortBindings']
assert {m['Destination']:m['Source'] for m in info['Mounts']}=={'/stage':str(stage),'/tests':str(root/'tools/staging')}
(art/'isolation.json').write_text(json.dumps({'network':'none','ports':info['HostConfig']['PortBindings'],'mounts':info['Mounts'],'image':info['Image']},indent=2))
(art/'shutdown-ready').unlink(missing_ok=True)
with (art/'test-client.log').open('w') as log:
 p=subprocess.Popen(['docker','exec',name,'python3','/tests/check_m1.py'],stdout=log,stderr=subprocess.STDOUT)
 deadline=time.monotonic()+(1800 if mode in ('m6asan','m7asan','m8asan') else 1200)
 while not (art/'shutdown-ready').exists():
  assert p.poll() is None, (art/'test-client.log').read_text()
  assert time.monotonic()<deadline,'test deadline exceeded; inspect staging logs'
  time.sleep(1)
 # check_m1 writes its JSON just after marker; ensure it is complete before shutdown.
 time.sleep(1)
 pending=int((art/'shutdown-ready').read_text())
 before=(art/'map-server.log').read_text()
 assert f'spawned id={pending}' in before and f'released id={pending}' not in before
 (art/'shutdown-checkpoint.json').write_text(json.dumps({'active_actor_before_signal':pending}))
 subprocess.run(['docker','stop','-t','35',name],check=True)
 p.wait(timeout=30);assert p.returncode==0
result=json.loads((art/'lifecycle-results.json').read_text());log=(art/'map-server.log').read_text();aid=result['shutdown_pending_actor']
assert f'released id={aid} detached=1 timers_clear=1' in log
if mode.startswith(('m6','m7','m8','m9')):
 import sqlite3
 db=sqlite3.connect(f'file:{stage}/ragoff-stage.sqlite3?mode=ro',uri=True)
 assert db.execute('SELECT base_exp FROM ragoff_companion WHERE id=?',(result['persistent_shutdown_profile'],)).fetchone()[0]=='789'
 db.close();result['persistent_shutdown_save']=True
else:
 assert f'released id={aid} detached=1 timers_clear=1 active=0' in log
assert (art/'exit-codes.txt').read_text()=='[0, 0, 0]',(art/'exit-codes.txt').read_text()
assert json.loads((art/'shutdown-checkpoint.json').read_text())['active_actor_before_signal']==aid
spawns=re.findall(r'Companion M1: spawned id=(\d+)',log)
releases=re.findall(r'Companion M1: released id=(\d+) detached=1 timers_clear=1',log)
assert sorted(spawns)==sorted(releases)
result.update(graceful_shutdown_with_actor=True,server_exit_codes=[0,0,0],all_spawned_released=len(spawns))
alllogs='\n'.join(p.read_text(errors='replace') for p in art.glob('*-server.log'))
assert not any(x in alllogs for x in ['ERROR: AddressSanitizer','ERROR: LeakSanitizer','cleanup invariant failed'])
result['asan_lsan_errors']=0 if mode.endswith('asan') else 'not instrumented'
result['ubsan_findings']=sorted(set(re.findall(r'[^\n]*runtime error:[^\n]*',alllogs)))
result['binary_sha256']={n:hashlib.sha256((stage/n).read_bytes()).hexdigest() for n in ('login-server','char-server','map-server')}
(art/'lifecycle-results.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
