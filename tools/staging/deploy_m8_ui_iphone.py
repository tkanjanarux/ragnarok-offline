#!/usr/bin/env python3
"""Staging only, M8 equipment UI wire extension; no schema/Char/production change."""
import pathlib,json,subprocess,hashlib,shutil,sqlite3,datetime,time,socket
r=pathlib.Path(__file__).resolve().parents[2];s=r/'runtime/iphone';name='ragoff-companion-iphone';h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
i=json.loads(subprocess.check_output(['docker','inspect',name]))[0]
assert i['HostConfig']['NetworkMode']==name
assert {m['Destination']:m['Source'] for m in i['Mounts']}=={'/stage':str(s),'/tests':str(r/'tools/staging')}
assert i['HostConfig']['PortBindings']=={f'{p}/tcp':[{'HostIp':'100.114.58.13','HostPort':str(p)}] for p in (16900,16121,15121)}
old='f7d30b555b70cb247918b71c0ac55b389a9fc01a1e811e24a9e888622d249f8a';assert h(s/'map-server')==old
assert h(r/'build-m1/bin/map-server')==h(r/'runtime/m8probe/map-server')
e=json.loads((r/'audit/evidence/m8-ui-results.json').read_text());assert e['gear_transfer_cycles']==100 and all(v for k,v in e.items() if k.startswith('ui_'))
assert (r/'runtime/m8probe/artifacts/exit-codes.txt').read_text()=='[0, 0, 0]'
assert 'REAL_SERVER_EQUIPMENT_SNAPSHOTS_PASS' in (r.parent/'client-build/companion-gear/tests.log').read_text()
shutil.copy2(s/'map-server',s/'map-server.m8-before-ui');shutil.copy2(r/'build-m1/bin/map-server',s/'map-server.ui-next')
subprocess.run(['docker','stop','-t','35',name],check=True)
b=s/('backup-m8-ui-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ'));b.mkdir(mode=0o700)
with sqlite3.connect(f'file:{s}/ragoff-stage.sqlite3?mode=ro',uri=True) as db,sqlite3.connect(b/'ragoff-stage.sqlite3') as out:db.backup(out)
(b/'ragoff-stage.sqlite3').chmod(0o600)
(s/'artifacts').rename(s/'artifacts-m8-before-ui');(s/'artifacts').mkdir();(s/'map-server.ui-next').replace(s/'map-server')
subprocess.run(['docker','start',name],check=True)
for _ in range(90):
 p=s/'artifacts/map-server.log'
 if p.exists() and 'Map Server is now online.' in p.read_text(errors='replace'):break
 time.sleep(1)
else:raise RuntimeError('staging readiness failed')
for p in (16900,16121,15121):
 with socket.create_connection(('100.114.58.13',p),5):pass
with sqlite3.connect(f'file:{b}/ragoff-stage.sqlite3?mode=ro',uri=True) as before,sqlite3.connect(f'file:{s}/ragoff-stage.sqlite3?mode=ro',uri=True) as after:
 for table in ('ragoff_companion','ragoff_companion_policy','ragoff_companion_gear','inventory','acc_reg_num'):
  if before.execute('SELECT count(*) FROM sqlite_master WHERE type="table" AND name=?',(table,)).fetchone()[0]:assert before.execute('SELECT * FROM '+table+' ORDER BY rowid').fetchall()==after.execute('SELECT * FROM '+table+' ORDER BY rowid').fetchall(),table
out={'map_sha256':h(s/'map-server'),'rollback_map_sha256':old,'backup':str(b),'production_changes':False,'database_migration':False,'preservation_check':True,'ports':[16900,16121,15121]}
(r/'audit/evidence/m8-ui-deployment.json').write_text(json.dumps(out,indent=2));print(json.dumps(out))
