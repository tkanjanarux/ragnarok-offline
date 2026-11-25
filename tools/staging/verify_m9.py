#!/usr/bin/env python3
import pathlib,subprocess,json,re,time,hashlib,sys
r=pathlib.Path(__file__).resolve().parents[2];mode=sys.argv[1];assert mode in ('m9','m9asan')
s=r/'runtime'/mode;a=s/'artifacts';name='ragoff-companion-'+mode
info=json.loads(subprocess.check_output(['docker','inspect',name]))[0];assert info['HostConfig']['NetworkMode']=='none' and not info['HostConfig']['PortBindings']
for check in ('progression','exp','gear','credit'):assert (a/f'm9-{check}-results.json').is_file(),check
recover='--check-stopped' in sys.argv
if not recover:
 p=subprocess.Popen(['docker','exec',name,'python3','/tests/check_m9_finish.py'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 end=time.monotonic()+60
 while not (a/'m9-shutdown-ready.json').exists():
  assert p.poll() is None,p.communicate()[0] if p.poll()!=None else ''
  assert time.monotonic()<end;time.sleep(.2)
 subprocess.run(['docker','stop','-t','35',name],check=True)
 out,_=p.communicate(timeout=20);assert p.returncode==0,out.decode()
else:
 assert not info['State']['Running'] and not info['State']['OOMKilled']
 assert len(json.loads((a/'m9-shutdown-ready.json').read_text()))==3
assert (a/'exit-codes.txt').read_text()=='[0, 0, 0]'
log=(a/'map-server.log').read_text(errors='replace')
spawns=re.findall(r'Companion M1: spawned id=(\d+)',log);released=re.findall(r'Companion M1: released id=(\d+) detached=1 timers_clear=1',log)
assert spawns and sorted(spawns)==sorted(released)
logs='\n'.join(f.read_text(errors='replace') for f in a.glob('*-server.log'))
assert not any(t in logs for t in ('ERROR: AddressSanitizer','ERROR: LeakSanitizer','cleanup invariant failed'))
ubsan=sorted(set(re.findall(r'[^\n]*runtime error:[^\n]*',logs)))
known=('msg_conf.cpp:135:','skill.cpp:181:','skill.cpp:212:')
reload_finding=any('homunculus.hpp:51:' in e for e in ubsan)
if reload_finding:
 # Newly observed during test-only @reloadmobdb, in byte-identical baseline parser.
 assert 'atcommand_reloadmobdb' in logs and 'HomunculusDatabase::parseBodyNode' in logs
 expected='9fbc5c349191063f181ebc3e83a75ea4d96fc452'
 assert subprocess.check_output(['git','hash-object','src/map/homunculus.cpp'],cwd=r,text=True).strip()==expected
 assert subprocess.check_output(['git','rev-parse','HEAD:src/map/homunculus.cpp'],cwd=r,text=True).strip()==expected
 known+=('homunculus.hpp:51:',)
assert all(any(x in e for x in known) for e in ubsan),ubsan
result={check:json.loads((a/f'm9-{check}-results.json').read_text()) for check in ('progression','exp','gear','credit')}
result.update(shutdown_checked_from_server_logs=recover,known_native_reload_bool_finding=reload_finding,all_spawned_released=len(spawns),shutdown_active_actors=3,server_exit_codes=[0,0,0],asan_lsan_errors=0 if mode.endswith('asan') else 'not instrumented',ubsan_findings=ubsan,binary_sha256={n:hashlib.sha256((s/n).read_bytes()).hexdigest() for n in ('map-server','char-server','login-server')})
(a/'m9-results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
