#!/usr/bin/env python3
"""M8 staging-only deployment with additive companion schema; never production."""
import pathlib,subprocess,json,hashlib,shutil,sqlite3,datetime,time,socket,yaml
root=pathlib.Path(__file__).resolve().parents[2];stage=root/'runtime/iphone';name='ragoff-companion-iphone'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
new=root/'build-m1/bin/map-server'
for mode in ('m8','m8asan'):
 e=json.loads((root/f'runtime/{mode}/artifacts/lifecycle-results.json').read_text())
 assert e['server_exit_codes']==[0,0,0] and e['all_spawned_released']>=119
 assert e['persistent_summon_bench_cycles']==100 and e['npc_click_dialogue_and_recruitment'] and e['same_account_other_character_isolation'] and e['persistent_shutdown_save']
 for k in ('policy_validation_and_owner_isolation','policy_failed_write_atomic','policy_none_suppresses_native_casts','policy_heal_before_resurrection_native_casts','policy_live_tank_vs_dps_targeting','policy_logout_persistence','policy_release_cleanup'): assert e[k],k
 assert e['gear_transfer_cycles']==100
 for k in ('gear_native_equipment_stats','gear_native_job_restrictions','gear_ownership_and_release_guard','gear_sql_failure_atomic','gear_equipment_save_failure_restores','gear_full_inventory_return_guard','gear_barrier_timeout_no_mutation','gear_pending_owner_logout_cleanup','gear_changed_instance_cancelled'): assert e[k],k
 for binary in ('login-server','char-server','map-server'): assert e['binary_sha256'][binary]==sha(root/('build-m1' if mode=='m8' else 'build-sanitize')/'bin'/binary)
 assert e['cycles']==100 and e['no_synthetic_db_rows'] and len(e['native_exp_share_cases'])==4
 for k in ('dead_actor_party_leave_and_rebind','dead_actor_owner_logout','dead_actor_shutdown','retained_corpse_and_native_ai_resurrection','wipe_no_field_revive_and_savepoint_recovery','native_sitting_and_natural_sp_regeneration','modern_party_options_effective_level_feedback','owner_targeted_skill_opener_wizard_assist','knight_protects_party_with_native_provoke'):
  assert e[k],k
 assert e['binary_sha256']['map-server']==sha(root/('build-m1' if mode=='m8' else 'build-sanitize')/'bin/map-server')
 if mode=='m8asan':
  assert e['asan_lsan_errors']==0
  assert all(any(loc in line for loc in ('src/common/msg_conf.cpp:135:', 'src/map/skill.cpp:181:', 'src/map/skill.cpp:212:')) for line in e['ubsan_findings']),e['ubsan_findings']
restart=json.loads((root/'audit/evidence/m8-restart-crash.json').read_text());assert restart['forced_map_crash_checkpoint_preserved']
info=json.loads(subprocess.check_output(['docker','inspect',name]))[0]
assert info['HostConfig']['NetworkMode']==name
assert info['HostConfig']['PortBindings']=={f'{port}/tcp':[{'HostIp':'100.114.58.13','HostPort':str(port)}] for port in (16900,16121,15121)}
assert {m['Destination']:m['Source'] for m in info['Mounts']}=={'/stage':str(stage),'/tests':str(root/'tools/staging')}
assert info['NetworkSettings']['Networks'][name]['IPAddress']=='172.27.0.2'
assert 'GEAR_SQL_OLD_SNAPSHOT_CRASH_DUPLICATE_FAILURE_LOAD_HANDOFF_PASS' in (root/'audit/evidence/m8-gear-guard-tests.log').read_text()
assert json.loads((root/'audit/evidence/m8-cash-purchase.json').read_text())['inventory_persisted']
assert json.loads((root/'audit/evidence/m8-rollback-test.json').read_text())['escrow_preserved']
assert restart['gear_native_stats_restored_after_crash']
oldhashes={'login-server':'5974147aff6bb1b5bfa2666dfac1d7ba02ab8db8a7f267ec4a65eccdc3b9e5c5','char-server':'bfa05cf386ac59357d26a6d692f7122561719c84ad171d945b56d121a6b03711','map-server':'44ac85e36ad71cfc57b010d4d5c9cf89bb4dd55aa20c2adf3804db8116a0c494'}
for binary,expected in oldhashes.items():
 assert sha(stage/binary)==expected,(binary,'live version mismatch')
 shutil.copy2(stage/binary,stage/(binary+'.m7-backup'))
 shutil.copy2(root/'build-m1/bin'/binary,stage/(binary+'.m8-next'))
 assert sha(root/'build-m1/bin'/binary)==sha(stage/(binary+'.m8-next'))
# Validate common SQLite database without printing connection fields.
conf=(stage/'conf/import/inter_conf.txt').read_text()
import re
names=re.findall(r'^\s*(?:login_server_db|char_server_db|map_server_db|ipban_db_db|log_db_db)\s*:\s*([^\s/]+)',conf,re.M)
assert names and all(x=='ragoff-stage' for x in names), 'shared staging SQLite required'
subprocess.run(['docker','stop','-t','35',name],check=True)
backup=stage/('backup-m7-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ'));backup.mkdir(mode=0o700)
c=sqlite3.connect(f'file:{stage}/ragoff-stage.sqlite3?mode=ro',uri=True)
with sqlite3.connect(backup/'ragoff-stage.sqlite3') as dst:c.backup(dst)
c.close();(backup/'ragoff-stage.sqlite3').chmod(0o600)
# Additive escrow table/release guard; existing player/config/profile rows untouched.
with sqlite3.connect(stage/'ragoff-stage.sqlite3') as db:
 db.executescript((root/'sqlite-files/companion/003_gear.sql').read_text())
(stage/'artifacts').rename(stage/'artifacts-m7-before-m8');(stage/'artifacts').mkdir()
for binary in oldhashes:(stage/(binary+'.m8-next')).replace(stage/binary)
subprocess.run(['docker','start',name],check=True)
end=time.monotonic()+90
while time.monotonic()<end:
 log=stage/'artifacts/map-server.log'
 if log.exists() and 'Map Server is now online.' in log.read_text(errors='replace'):break
 time.sleep(1)
else:raise RuntimeError('Staging failed readiness: inspect artifacts; use M7 map with M8 Char custody guard')
for port in (16900,16121,15121):
 with socket.create_connection(('100.114.58.13',port),5):pass
# Read-only post-deployment preservation checks against the post-stop backup.
with sqlite3.connect(f'file:{backup}/ragoff-stage.sqlite3?mode=ro',uri=True) as before, sqlite3.connect(f'file:{stage}/ragoff-stage.sqlite3?mode=ro',uri=True) as after:
 for table in ('ragoff_companion','ragoff_companion_policy','inventory'):
  assert before.execute('SELECT * FROM '+table+' ORDER BY rowid').fetchall()==after.execute('SELECT * FROM '+table+' ORDER BY rowid').fetchall(),table
 for table in ('acc_reg_num','acc_reg_num_db'):
  if before.execute('SELECT count(*) FROM sqlite_master WHERE type="table" AND name=?',(table,)).fetchone()[0]:
   assert before.execute('SELECT * FROM '+table+' ORDER BY rowid').fetchall()==after.execute('SELECT * FROM '+table+' ORDER BY rowid').fetchall(),table
receipt=dict(binary_sha256=sha(stage/'map-server'),rollback_sha256=oldhashes['map-server'],backup=str(backup),container=name,address='100.114.58.13:16900',ports_verified=[16900,16121,15121],production_changes=False,database_mutations="additive companion gear escrow and profile release guard only")
(root/'audit/evidence/m8-staging-deployment.json').write_text(json.dumps(receipt,indent=2));print(json.dumps(receipt))
