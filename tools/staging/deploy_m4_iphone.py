#!/usr/bin/env python3
"""Deploy ONLY the known isolated iPhone staging container after both test suites pass."""
import pathlib,subprocess,json,hashlib,shutil,sqlite3,datetime,time,socket
root=pathlib.Path(__file__).resolve().parents[2];stage=root/'runtime/iphone';name='ragoff-companion-iphone'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
new=root/'build-m1/bin/map-server'
for mode in ('m4','m4asan'):
 evidence=json.loads((root/f'runtime/{mode}/artifacts/lifecycle-results.json').read_text())
 assert evidence['server_exit_codes']==[0,0,0] and evidence['all_spawned_released']==115
 assert evidence['cycles']==100 and evidence['no_synthetic_db_rows']
 assert evidence['priest_native_resurrection'] and evidence['wizard_native_skill_damage_and_death']
 assert len(evidence['native_exp_share_cases'])==4
 assert evidence['binary_sha256']['map-server']==sha(root/('build-m1' if mode=='m4' else 'build-sanitize')/'bin/map-server')
 if mode=='m4asan':
  assert evidence['asan_lsan_errors']==0
  assert all(any(loc in line for loc in ('src/common/msg_conf.cpp:135:', 'src/map/skill.cpp:181:', 'src/map/skill.cpp:212:')) for line in evidence['ubsan_findings']),evidence['ubsan_findings']
info=json.loads(subprocess.check_output(['docker','inspect',name]))[0]
assert info['HostConfig']['NetworkMode']==name
expected_ports={f'{port}/tcp':[{'HostIp':'100.114.58.13','HostPort':str(port)}] for port in (16900,16121,15121)}
assert info['HostConfig']['PortBindings']==expected_ports # Existing Tailscale-only staging bindings
assert {m['Destination']:m['Source'] for m in info['Mounts']}=={'/stage':str(stage),'/tests':str(root/'tools/staging')}
assert info['NetworkSettings']['Networks'][name]['IPAddress']=='172.27.0.2'
oldsha='f89d8205abd5c162f2c009ecc50c10e3fb7a12348301ea15e7432279dbbd2de5'
assert sha(stage/'map-server')==oldsha
assert not (stage/'m4-cash-grant.json').exists(),'M4 grant already applied; do not repeat'
shutil.copy2(stage/'map-server',stage/'map-server.m3-backup')
shutil.copy2(new,stage/'map-server.m4-next')
assert sha(new)==sha(stage/'map-server.m4-next')
subprocess.run(['docker','stop','-t','35',name],check=True)
backup=stage/('backup-m3-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ'));backup.mkdir(mode=0o700)
c=sqlite3.connect(stage/'ragoff-stage.sqlite3')
with sqlite3.connect(backup/'ragoff-stage.sqlite3') as dst:c.backup(dst)
(backup/'ragoff-stage.sqlite3').chmod(0o600)
shutil.copy2(stage/'db/import/item_cash.yml',backup/'item_cash.yml')
c.execute('BEGIN IMMEDIATE')
assert c.execute('select count(*) from char where online<>0').fetchone()[0]==0
account=2000001
before=c.execute('select value from acc_reg_num where account_id=? and key=? and "index"=0',(account,'#CASHPOINTS')).fetchone();before=before[0] if before else 0
party_before=c.execute('select party_id,exp from party where leader_id=? and leader_char=?',(account,150001)).fetchall()
# Enable the user's existing staging test party for the requested EXP acceptance test.
c.execute('update party set exp=1 where leader_id=? and leader_char=?',(account,150001))
c.execute('insert into acc_reg_num(account_id,key,"index",value) values(?,?,0,?) on conflict(account_id,key,"index") do update set value=excluded.value',(account,'#CASHPOINTS',before+10000));c.commit();c.close()
receipt={'account_id':account,'cash_before':before,'cash_after':before+10000,'backup':str(backup),'test_party_exp_before':party_before,'test_party_exp_after':1 if party_before else None}
(stage/'m4-cash-grant.json').write_text(json.dumps(receipt,indent=2));(stage/'m4-cash-grant.json').chmod(0o600)
shutil.copy2(root.parent/'cash-shop/item_cash.pagination.yml',stage/'db/import/item_cash.yml')
(stage/'artifacts').rename(stage/'artifacts-m3-before-m4');(stage/'artifacts').mkdir()
(stage/'map-server.m4-next').replace(stage/'map-server')
subprocess.run(['docker','start',name],check=True)
end=time.monotonic()+90
while time.monotonic()<end:
 log=stage/'artifacts/map-server.log'
 if log.exists() and 'Map Server is now online.' in log.read_text(errors='replace'):break
 time.sleep(1)
else:raise RuntimeError('Staging failed readiness: restore map-server.m3-backup; inspect artifacts')
for port in (16900,16121,15121):
 with socket.create_connection(('100.114.58.13',port),5):pass
receipt.update(binary_sha256=sha(stage/'map-server'),rollback_sha256=sha(stage/'map-server.m3-backup'),catalog_items=30,container=name,network=name,address='100.114.58.13:16900',ports_verified=[16900,16121,15121],production_companion_changes=False)
(root/'audit/evidence/m4-staging-deployment.json').write_text(json.dumps(receipt,indent=2));print(json.dumps(receipt))
