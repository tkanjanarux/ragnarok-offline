#!/usr/bin/env python3
"""One additional optimized restart with the same SQLite file, not a restored backup."""
import pathlib,json,subprocess,re,time
r=pathlib.Path(__file__).resolve().parents[2];s=r/'runtime/m93';a=s/'artifacts';name='ragoff-companion-m93'
assert json.loads(subprocess.check_output(['docker','inspect',name]))[0]['State']['Running']==False
source=a/'m93-verification.json'
if not source.exists():source=s/'artifacts-before-restart/m93-verification.json'
summary=json.loads(source.read_text());backup=s/'artifacts-before-restart'
if backup.exists():backup=s/f'artifacts-restart-attempt-{int(time.time())}'
a.rename(backup);a.mkdir()
subprocess.run(['docker','start',name],check=True)
p=subprocess.run(['docker','exec',name,'python3','/tests/check_m93_restart.py'],capture_output=True,timeout=180)
subprocess.run(['docker','stop','-t','35',name],check=True)
assert p.returncode==0,(p.stdout+p.stderr).decode()
assert (a/'exit-codes.txt').read_text()=='[0, 0, 0]'
log=(a/'map-server.log').read_text(errors='replace');spawns=re.findall(r'Companion M1: spawned id=(\d+)',log);released=re.findall(r'Companion M1: released id=(\d+) detached=1 timers_clear=1',log);assert sorted(spawns)==sorted(released)
summary['restart']=json.loads((a/'m93-restart-results.json').read_text());summary['restart']['all_spawned_released']=len(spawns)
(a/'m93-verification.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary['restart']))

(r/'audit/evidence/m93-restart.json').write_text(json.dumps(summary['restart'],indent=2))
