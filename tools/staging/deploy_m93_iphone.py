#!/usr/bin/env python3
"""Deploy only isolated iPhone Staging; durable stack guard requires updated Char + Map."""
import pathlib,json,subprocess,hashlib,shutil,sqlite3,datetime,time,socket
r=pathlib.Path(__file__).resolve().parents[2];s=r/'runtime/iphone';name='ragoff-companion-iphone';h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
i=json.loads(subprocess.check_output(['docker','inspect',name]))[0]
assert i['HostConfig']['NetworkMode']==name
assert {m['Destination']:m['Source'] for m in i['Mounts']}=={'/stage':str(s),'/tests':str(r/'tools/staging')}
assert i['HostConfig']['PortBindings']=={f'{p}/tcp':[{'HostIp':'100.114.58.13','HostPort':str(p)}] for p in (16900,16121,15121)}
old={'map-server':'13bdfb21fed7e78fa5111226c5ef0fa0b66cb17fff6b649ba63bc05427a75fc2','char-server':'bb3f4ed80bbc78e266371d11b851edb95ea1885da89f52547b6d8a0edc2f91ba'}
assert all(h(s/n)==sha for n,sha in old.items());login=h(s/'login-server')
new={n:h(r/'build-m1/bin'/n) for n in old}
for mode in ('m93','m93asan','m93regress'):
 e=json.loads((r/f'audit/evidence/{mode}-verification.json').read_text());assert e['server_exit_codes']==[0,0,0]
 if mode!='m93asan':assert all(e['binary_sha256'][n]==v for n,v in new.items())
 else:assert e['asan_lsan_errors']==0
 if mode=='m93regress':assert e['tests']['regression']['gear_transfer_cycles']==100
 else:assert e['tests']['supplies']['transfer_cycles']==100 and e['tests']['faults']['resource_commit_failure_rolls_back_stock_and_hp_sp']
 assert json.loads((r/f'audit/evidence/{mode}-persistence-scan.json').read_text())['synthetic_rows']==0
assert json.loads((r/'audit/evidence/m93-restart.json').read_text())['supply_counts_preserved']
assert 'SUPPLY_STALE_SAVE_CRASH_ACK_SQL_FAILURE_CAPACITY_OWNERSHIP_PASS' in (r/'audit/evidence/m93-supply-guard.log').read_text()
assert json.loads((r/'runtime/m93oldchar/artifacts/m93-oldchar.json').read_text())['old_char_capability_rejected']
assert all(x['rejected_before_online'] for x in json.loads((r/'audit/evidence/m93-startup-guards.json').read_text()).values())
off=json.loads((r/'runtime/m9off/artifacts/lifecycle-results.json').read_text());assert off['all_spawned_released']==239 and all(off['binary_sha256'][n]==v for n,v in new.items())
b=s/('backup-m93-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ'));b.mkdir(mode=0o700)
for n in old:shutil.copy2(s/n,b/n);shutil.copy2(r/'build-m1/bin'/n,s/(n+'.m93-next'))
shutil.copy2(s/'conf/import/battle_conf.txt',b/'battle_conf.txt')
subprocess.run(['docker','stop','-t','60',name],check=True)
with sqlite3.connect(f'file:{s}/ragoff-stage.sqlite3?mode=ro',uri=True) as src,sqlite3.connect(b/'ragoff-stage.sqlite3') as dst:src.backup(dst)
(b/'ragoff-stage.sqlite3').chmod(0o600)
try:
 with sqlite3.connect(s/'ragoff-stage.sqlite3') as db:db.executescript((r/'sqlite-files/companion/005_supplies.sql').read_text())
 with (s/'conf/import/battle_conf.txt').open('a') as f:f.write('\n// M9.3: native potion use + Char snapshot journal guard\ncompanion_supplies: 1\n')
 (s/'artifacts').rename(b/'artifacts-before');(s/'artifacts').mkdir()
 for n in old:(s/(n+'.m93-next')).replace(s/n)
 subprocess.run(['docker','start',name],check=True)
 for _ in range(120):
  p=s/'artifacts/map-server.log'
  if p.exists() and 'Map Server is now online.' in p.read_text(errors='replace'):break
  time.sleep(1)
 else:raise RuntimeError('staging readiness failed')
 for port in (16900,16121,15121):
  with socket.create_connection(('100.114.58.13',port),5):pass
 with sqlite3.connect(f'file:{b}/ragoff-stage.sqlite3?mode=ro',uri=True) as before,sqlite3.connect(f'file:{s}/ragoff-stage.sqlite3?mode=ro',uri=True) as after:
  for table in ('ragoff_companion','ragoff_companion_growth','ragoff_companion_policy','ragoff_companion_gear','inventory','acc_reg_num','char','party'):
   assert before.execute('SELECT * FROM '+table+' ORDER BY rowid').fetchall()==after.execute('SELECT * FROM '+table+' ORDER BY rowid').fetchall(),table
  assert after.execute('SELECT count(*) FROM ragoff_companion_supply_journal').fetchone()[0]==0
  assert after.execute('SELECT count(*) FROM ragoff_companion_supply').fetchone()[0]==0
 assert h(s/'login-server')==login
except Exception:
 subprocess.run(['docker','stop','-t','60',name],check=True)
 # Roll Map/config back; keep the updated Char guard if any journals now exist.
 shutil.copy2(b/'map-server',s/'map-server');shutil.copy2(b/'battle_conf.txt',s/'conf/import/battle_conf.txt')
 subprocess.run(['docker','start',name],check=True)
 raise
receipt=dict(binary_sha256=new,previous_binary_sha256=old,login_unchanged_sha256=login,backup=str(b),production_changes=False,migration='005_supplies.sql',preservation_check=True,native_iphone='UNVERIFIED')
(r/'audit/evidence/m93-deployment.json').write_text(json.dumps(receipt,indent=2));print(json.dumps(receipt,indent=2))
