#!/usr/bin/env python3
"""M7 staging-only deployment with additive companion schema; never production."""
import pathlib,subprocess,json,hashlib,shutil,sqlite3,datetime,time,socket,yaml
root=pathlib.Path(__file__).resolve().parents[2];stage=root/'runtime/iphone';name='ragoff-companion-iphone'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
new=root/'build-m1/bin/map-server'
for mode in ('m7','m7asan'):
 e=json.loads((root/f'runtime/{mode}/artifacts/lifecycle-results.json').read_text())
 assert e['server_exit_codes']==[0,0,0] and e['all_spawned_released']>=119
 assert e['persistent_summon_bench_cycles']==100 and e['npc_click_dialogue_and_recruitment'] and e['same_account_other_character_isolation'] and e['persistent_shutdown_save']
 for k in ('policy_validation_and_owner_isolation','policy_failed_write_atomic','policy_none_suppresses_native_casts','policy_heal_before_resurrection_native_casts','policy_live_tank_vs_dps_targeting','policy_logout_persistence','policy_release_cleanup'): assert e[k],k
 assert e['cycles']==100 and e['no_synthetic_db_rows'] and len(e['native_exp_share_cases'])==4
 for k in ('dead_actor_party_leave_and_rebind','dead_actor_owner_logout','dead_actor_shutdown','retained_corpse_and_native_ai_resurrection','wipe_no_field_revive_and_savepoint_recovery','native_sitting_and_natural_sp_regeneration','modern_party_options_effective_level_feedback','owner_targeted_skill_opener_wizard_assist','knight_protects_party_with_native_provoke'):
  assert e[k],k
 assert e['binary_sha256']['map-server']==sha(root/('build-m1' if mode=='m7' else 'build-sanitize')/'bin/map-server')
 if mode=='m7asan':
  assert e['asan_lsan_errors']==0
  assert all(any(loc in line for loc in ('src/common/msg_conf.cpp:135:', 'src/map/skill.cpp:181:', 'src/map/skill.cpp:212:')) for line in e['ubsan_findings']),e['ubsan_findings']
restart=json.loads((root/'audit/evidence/m7-restart-crash.json').read_text());assert restart['forced_map_crash_checkpoint_preserved']
info=json.loads(subprocess.check_output(['docker','inspect',name]))[0]
assert info['HostConfig']['NetworkMode']==name
assert info['HostConfig']['PortBindings']=={f'{port}/tcp':[{'HostIp':'100.114.58.13','HostPort':str(port)}] for port in (16900,16121,15121)}
assert {m['Destination']:m['Source'] for m in info['Mounts']}=={'/stage':str(stage),'/tests':str(root/'tools/staging')}
assert info['NetworkSettings']['Networks'][name]['IPAddress']=='172.27.0.2'
oldsha='28d9ceb9f99e9db0a735cfa29779c9711056fe855b9d7f9ec762e6d662a455ef'
assert sha(stage/'map-server')==oldsha
shutil.copy2(stage/'map-server',stage/'map-server.m6-backup')
shutil.copy2(new,stage/'map-server.m7-next');assert sha(new)==sha(stage/'map-server.m7-next')
subprocess.run(['docker','stop','-t','35',name],check=True)
backup=stage/('backup-m6-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ'));backup.mkdir(mode=0o700)
c=sqlite3.connect(f'file:{stage}/ragoff-stage.sqlite3?mode=ro',uri=True)
with sqlite3.connect(backup/'ragoff-stage.sqlite3') as dst:c.backup(dst)
c.close();(backup/'ragoff-stage.sqlite3').chmod(0o600)
# Additive policy table/cleanup trigger only; existing player/config/profile rows untouched.
with sqlite3.connect(stage/'ragoff-stage.sqlite3') as db:
 db.executescript((root/'sqlite-files/companion/002_policy.sql').read_text())
(stage/'artifacts').rename(stage/'artifacts-m6-before-m7');(stage/'artifacts').mkdir()
(stage/'map-server.m7-next').replace(stage/'map-server')
subprocess.run(['docker','start',name],check=True)
end=time.monotonic()+90
while time.monotonic()<end:
 log=stage/'artifacts/map-server.log'
 if log.exists() and 'Map Server is now online.' in log.read_text(errors='replace'):break
 time.sleep(1)
else:raise RuntimeError('Staging failed readiness: restore map-server.m6-backup; inspect artifacts')
for port in (16900,16121,15121):
 with socket.create_connection(('100.114.58.13',port),5):pass
receipt=dict(binary_sha256=sha(stage/'map-server'),rollback_sha256=oldsha,backup=str(backup),container=name,address='100.114.58.13:16900',ports_verified=[16900,16121,15121],production_changes=False,database_mutations="additive companion policy table and cleanup trigger only")
(root/'audit/evidence/m7-staging-deployment.json').write_text(json.dumps(receipt,indent=2));print(json.dumps(receipt))
