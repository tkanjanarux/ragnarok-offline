#!/usr/bin/env python3
import pathlib,shutil,sqlite3,subprocess,json,os
r=pathlib.Path(__file__).resolve().parents[2];source=r/'runtime/m93regress';assert (source/'M9_TEST').exists();result={}
for case in ('missing-migration','no-progression'):
 out=r/'runtime'/('m93-guard-'+case);assert not out.exists();out.mkdir()
 for n in ('conf','db','npc'):shutil.copytree(source/n,out/n)
 shutil.copy2(r/'build-m1/bin/map-server',out/'map-server');(out/'log').mkdir();(out/'save').mkdir()
 with sqlite3.connect(f'file:{source}/ragoff-stage.sqlite3?mode=ro',uri=True) as old,sqlite3.connect(out/'ragoff-stage.sqlite3') as new:
  old.backup(new)
  if case=='missing-migration':new.execute('DROP TABLE ragoff_companion_supply_journal');new.commit()
 if case=='no-progression':
  with (out/'conf/import/battle_conf.txt').open('a') as f:f.write('\ncompanion_owner_progression: 0\ncompanion_loadouts: 0\n')
 p=subprocess.run(['docker','run','--rm','--network','none','--user',f'{os.getuid()}:{os.getgid()}','--cap-drop','ALL','--security-opt','no-new-privileges','--mount',f'type=bind,src={out},dst=/stage','--workdir','/stage','ragoff-companion-staging:m1','./map-server'],capture_output=True,timeout=90)
 log=(p.stdout+p.stderr).decode(errors='replace');assert p.returncode!=0 and 'supplies require owner progression and migration 005' in log and 'Map Server is now online.' not in log
 (out/'result.log').write_text(log);result[case]=dict(rejected_before_online=True,exit_code=p.returncode)
(r/'audit/evidence/m93-startup-guards.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
