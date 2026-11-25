#!/usr/bin/env python3
"""Prove invalid progression config fails before accepting players, disposable DBs only."""
import pathlib,shutil,sqlite3,subprocess,json,os
r=pathlib.Path(__file__).resolve().parents[2];source=r/'runtime/m92off';assert (source/'M9_TEST').exists()
results={}
for case,expected in (('loadout-without-progression','loadouts require owner progression'),):
 out=r/'runtime'/('m92-guard-'+case);assert not out.exists();out.mkdir()
 for name in ('conf',):shutil.copytree(source/name,out/name)
 for name in ('db','npc'):shutil.copytree(source/name,out/name)
 shutil.copy2(r/'build-m1/bin/map-server',out/'map-server');(out/'log').mkdir();(out/'save').mkdir()
 with sqlite3.connect(f'file:{source}/ragoff-stage.sqlite3?mode=ro',uri=True) as old,sqlite3.connect(out/'ragoff-stage.sqlite3') as new:
  old.backup(new)
  if case=='missing-migration':new.execute('DROP TABLE ragoff_companion_growth');new.commit()
 if case=='loadout-without-progression':
  with (out/'conf/import/battle_conf.txt').open('a') as f:f.write('\ncompanion_owner_progression: 0\ncompanion_loadouts: 1\n')
 p=subprocess.run(['docker','run','--rm','--network','none','--user',f'{os.getuid()}:{os.getgid()}','--cap-drop','ALL','--security-opt','no-new-privileges','--mount',f'type=bind,src={out},dst=/stage','--workdir','/stage','ragoff-companion-staging:m1','./map-server'],capture_output=True,timeout=90)
 log=(p.stdout+p.stderr).decode(errors='replace');assert p.returncode!=0 and expected in log,(case,p.returncode,log[-2000:]);assert 'Map Server is now online.' not in log
 (out/'result.log').write_text(log);results[case]={'exit_code':p.returncode,'rejected_before_online':True}
(r/'audit/evidence/m92-startup-guards.json').write_text(json.dumps(results,indent=2));print(json.dumps(results))
