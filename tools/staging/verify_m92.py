#!/usr/bin/env python3
"""Verify M9.2 fixture shutdown, lifecycle and sanitizer evidence."""
import pathlib,subprocess,json,re,time,hashlib,sys,sqlite3
r=pathlib.Path(__file__).resolve().parents[2];mode=sys.argv[1];assert mode in ('m92','m92asan')
s=r/'runtime'/mode;a=s/'artifacts';name='ragoff-companion-'+mode
info=json.loads(subprocess.check_output(['docker','inspect',name]))[0]
assert info['HostConfig']['NetworkMode']=='none' and not info['HostConfig']['PortBindings']
test=json.loads((a/'m92-results.json').read_text());assert test['loan_summon_cycles']==test['gear_transfer_cycles']==100
p=subprocess.Popen(['docker','exec',name,'python3','/tests/check_m9_finish.py'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
end=time.monotonic()+90
while not (a/'m9-shutdown-ready.json').exists():
 assert p.poll() is None,p.communicate()[0]
 assert time.monotonic()<end;time.sleep(.2)
subprocess.run(['docker','stop','-t','60',name],check=True)
out,_=p.communicate(timeout=20);assert p.returncode==0,out.decode()
assert (a/'exit-codes.txt').read_text()=='[0, 0, 0]'
logs='\n'.join(f.read_text(errors='replace') for f in a.glob('*-server.log'))
spawns=re.findall(r'Companion M1: spawned id=(\d+)',logs);released=re.findall(r'Companion M1: released id=(\d+) detached=1 timers_clear=1',logs)
assert spawns and sorted(spawns)==sorted(released)
assert not any(t in logs for t in ('ERROR: AddressSanitizer','ERROR: LeakSanitizer','cleanup invariant failed'))
ubsan=sorted(set(re.findall(r'[^\n]*runtime error:[^\n]*',logs)))
assert all(any(x in e for x in ('msg_conf.cpp:135:','skill.cpp:181:','skill.cpp:212:')) for e in ubsan),ubsan
with sqlite3.connect(f'file:{s}/ragoff-stage.sqlite3?mode=ro',uri=True) as db:
 for table in ('inventory','cart_inventory','storage','guild_storage','ragoff_companion_gear'):
  for (uid,) in db.execute('SELECT unique_id FROM '+table):
   assert (int(uid or 0)&0xf000000000000000)!=0xf000000000000000,(table,uid)
result=dict(tests=test,loan_uids_persisted=0,all_spawned_released=len(spawns),shutdown_active_actors=3,server_exit_codes=[0,0,0],asan_lsan_errors=0 if mode.endswith('asan') else 'not instrumented',ubsan_findings=ubsan,binary_sha256={n:hashlib.sha256((s/n).read_bytes()).hexdigest() for n in ('map-server','char-server','login-server')})
(a/'m92-verification.json').write_text(json.dumps(result,indent=2))
(r/f'audit/evidence/{mode}-verification.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
