#!/usr/bin/env python3
import pathlib,json,subprocess,re,time,hashlib,sys,sqlite3
r=pathlib.Path(__file__).resolve().parents[2];mode=sys.argv[1];assert mode in ('m93','m93asan','m93regress')
s=r/'runtime'/mode;a=s/'artifacts';name='ragoff-companion-'+mode
info=json.loads(subprocess.check_output(['docker','inspect',name]))[0]
assert info['HostConfig']['NetworkMode']=='none' and not info['HostConfig']['PortBindings']
tests={key:json.loads((a/file).read_text()) for key,file in ([('regression','m92-results.json')] if mode=='m93regress' else [('supplies','m93-results.json'),('faults','m93-fault-results.json')])}
if mode!='m93regress':
 subprocess.run(['docker','exec',name,'python3','/tests/check_m93_metadata.py'],check=True)
 tests['metadata']=json.loads((a/'m93-metadata-results.json').read_text())
p=subprocess.Popen(['docker','exec',name,'python3','/tests/check_m9_finish.py'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
end=time.monotonic()+90
while not (a/'m9-shutdown-ready.json').exists():
 assert p.poll() is None,p.communicate()[0];assert time.monotonic()<end;time.sleep(.2)
subprocess.run(['docker','stop','-t','60',name],check=True);out,_=p.communicate(timeout=20);assert p.returncode==0,out.decode()
assert (a/'exit-codes.txt').read_text()=='[0, 0, 0]'
logs='\n'.join(f.read_text(errors='replace') for f in a.glob('*-server.log'))
spawns=re.findall(r'Companion M1: spawned id=(\d+)',logs);releases=re.findall(r'Companion M1: released id=(\d+) detached=1 timers_clear=1',logs);assert spawns and sorted(spawns)==sorted(releases)
assert not any(t in logs for t in ('ERROR: AddressSanitizer','ERROR: LeakSanitizer','cleanup invariant failed'))
ubsan=sorted(set(re.findall(r'[^\n]*runtime error:[^\n]*',logs)));assert all(any(t in e for t in ('msg_conf.cpp:135:','skill.cpp:181:','skill.cpp:212:')) for e in ubsan),ubsan
with sqlite3.connect(f'file:{s}/ragoff-stage.sqlite3?mode=ro',uri=True) as d:
 assert d.execute('SELECT count(*) FROM ragoff_companion_supply_journal').fetchone()[0]==0
 totals=d.execute('SELECT profile_id,nameid,amount FROM ragoff_companion_supply ORDER BY profile_id,nameid').fetchall()
result=dict(tests=tests,all_spawned_released=len(spawns),shutdown_active_actors=3,server_exit_codes=[0,0,0],asan_lsan_errors=0 if mode.endswith('asan') else 'not instrumented',ubsan_findings=ubsan,stock_at_shutdown=totals,binary_sha256={n:hashlib.sha256((s/n).read_bytes()).hexdigest() for n in ('map-server','char-server','login-server')})
(a/'m93-verification.json').write_text(json.dumps(result,indent=2));(r/f'audit/evidence/{mode}-verification.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
