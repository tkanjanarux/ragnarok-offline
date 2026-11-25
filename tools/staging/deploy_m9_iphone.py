#!/usr/bin/env python3
"""Guarded Staging-only M9.1 deployment; no Production endpoints or credentials."""
import pathlib,json,subprocess,hashlib,shutil,sqlite3,datetime,time,socket
r=pathlib.Path(__file__).resolve().parents[2];s=r/'runtime/iphone';name='ragoff-companion-iphone'
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
i=json.loads(subprocess.check_output(['docker','inspect',name]))[0]
assert i['HostConfig']['NetworkMode']==name
assert {m['Destination']:m['Source'] for m in i['Mounts']}=={'/stage':str(s),'/tests':str(r/'tools/staging')}
assert i['HostConfig']['PortBindings']=={f'{p}/tcp':[{'HostIp':'100.114.58.13','HostPort':str(p)}] for p in (16900,16121,15121)}
old='9f2b9561ea865dc3e09b66af1bf301d05775e0ecbd0b73533a667275069f8d46';assert h(s/'map-server')==old
new=h(r/'build-m1/bin/map-server')
for mode in ('m9','m9asan'):
 e=json.loads((r/f'runtime/{mode}/artifacts/m9-results.json').read_text())
 assert e['server_exit_codes']==[0,0,0] and e['progression']['resource_stable_summon_cycles']==100 and e['gear']['gear_transfer_cycles']==100
 assert len(e['exp'])==18
 assert e['credit']['dead_companion_previous_damage_owner_exp']==149 and e['credit']['dead_owner_exp']==0
 if mode=='m9':assert e['binary_sha256']['map-server']==new
 else:assert e['asan_lsan_errors']==0
 scan=json.loads((r/f'audit/evidence/{mode}-persistence-scan.json').read_text());assert scan['synthetic_rows']==0
reg=json.loads((r/'runtime/m9off/artifacts/lifecycle-results.json').read_text());assert reg['all_spawned_released']==239 and reg['binary_sha256']['map-server']==new
assert all(v['rejected_before_online'] for v in json.loads((r/'audit/evidence/m9-startup-guards.json').read_text()).values())
for binary in ('char-server','login-server'):assert h(s/binary)==reg['binary_sha256'][binary]
b=s/('backup-m9-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ'));b.mkdir(mode=0o700)
shutil.copy2(s/'map-server',b/'map-server');shutil.copy2(s/'conf/import/battle_conf.txt',b/'battle_conf.txt')
shutil.copy2(r/'build-m1/bin/map-server',s/'map-server.m9-next')
subprocess.run(['docker','stop','-t','35',name],check=True)
with sqlite3.connect(f'file:{s}/ragoff-stage.sqlite3?mode=ro',uri=True) as src,sqlite3.connect(b/'ragoff-stage.sqlite3') as dst:src.backup(dst)
(b/'ragoff-stage.sqlite3').chmod(0o600)
try:
 with sqlite3.connect(s/'ragoff-stage.sqlite3') as db:db.executescript((r/'sqlite-files/companion/004_owner_progression.sql').read_text())
 with (s/'conf/import/battle_conf.txt').open('a') as f:f.write('\n// M9.1: paired owner progression + real-player EXP (startup-only)\ncompanion_owner_progression: 1\n')
 (s/'artifacts').rename(b/'artifacts-before');(s/'artifacts').mkdir()
 (s/'map-server.m9-next').replace(s/'map-server')
 subprocess.run(['docker','start',name],check=True)
 for _ in range(120):
  p=s/'artifacts/map-server.log'
  if p.exists() and 'Map Server is now online.' in p.read_text(errors='replace'):break
  time.sleep(1)
 else:raise RuntimeError('staging readiness failed')
 assert 'owner progression and owner EXP routing enabled' in p.read_text(errors='replace')
 for port in (16900,16121,15121):
  with socket.create_connection(('100.114.58.13',port),5):pass
 with sqlite3.connect(f'file:{b}/ragoff-stage.sqlite3?mode=ro',uri=True) as before,sqlite3.connect(f'file:{s}/ragoff-stage.sqlite3?mode=ro',uri=True) as after:
  for table in ('ragoff_companion','ragoff_companion_policy','ragoff_companion_gear','inventory','acc_reg_num','char','party'):
   assert before.execute('SELECT * FROM '+table+' ORDER BY rowid').fetchall()==after.execute('SELECT * FROM '+table+' ORDER BY rowid').fetchall(),table
except Exception:
 subprocess.run(['docker','stop','-t','35',name],check=True)
 shutil.copy2(b/'map-server',s/'map-server');shutil.copy2(b/'battle_conf.txt',s/'conf/import/battle_conf.txt')
 # Keep additive migration; do not roll back player state or escrow.
 with sqlite3.connect(s/'ragoff-stage.sqlite3') as db:db.execute('DELETE FROM ragoff_companion_growth')
 subprocess.run(['docker','start',name],check=True)
 raise
receipt=dict(map_sha256=new,rollback_map_sha256=old,backup=str(b),production_changes=False,migration='004_owner_progression.sql',preservation_check=True,ports=[16900,16121,15121],native_iphone='UNVERIFIED')
(r/'audit/evidence/m9-deployment.json').write_text(json.dumps(receipt,indent=2));print(json.dumps(receipt,indent=2))
