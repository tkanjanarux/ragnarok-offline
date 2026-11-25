#!/usr/bin/env python3
"""Create a disposable, fresh-schema runtime. Never opens or copies a player DB."""
import pathlib, shutil, sqlite3, secrets, json, hashlib, sys
root=pathlib.Path(__file__).resolve().parents[2]
mode=sys.argv[1] if len(sys.argv)>1 else 'baseline'
assert mode in ('baseline','m1','asan','m2','m2asan','m3','m3asan','m3debug','m4','m4asan','m4debug','m4probe','m5','m5asan','m6','m6asan','m7','m7asan','m8','m8asan','m8probe','m9','m9asan','m9off','m9job','m92','m92asan','m92off','m93','m93asan','m93regress','m93oldchar')
binaries=(pathlib.Path(sys.argv[2]).resolve() if len(sys.argv)>2 else root)
assert binaries.is_relative_to(root), 'binaries must belong to this development checkout'
out=root/'runtime'/mode
assert not out.exists(), f'{out} already exists; choose a fresh run explicitly'
out.mkdir(parents=True)
if mode.startswith(('m2','m3','m4','m5','m6','m7','m8','m9')): (out/'M2_TEST').touch()
if mode.startswith(('m3','m4','m5','m6','m7','m8','m9')): (out/'M3_TEST').touch()
if mode.startswith(('m4','m5','m6','m7','m8','m9')): (out/'M4_TEST').touch()
if mode.startswith(('m5','m6','m7','m8','m9')): (out/'M5_TEST').touch()
if mode.startswith(('m6','m7','m8','m9')): (out/'M6_TEST').touch()
if mode.startswith(('m7','m8','m9')): (out/'M7_TEST').touch()
if mode.startswith(('m8','m9')): (out/'M8_TEST').touch()
for name in ('conf','db','npc'):
 shutil.copytree(root/name,out/name)
for name in ('login-server','char-server','map-server'):
 shutil.copy2(binaries/name,out/name)
(out/'log').mkdir(); (out/'save').mkdir(); (out/'artifacts').mkdir()
internal=secrets.token_hex(10); player=secrets.token_hex(10)
conf=out/'conf/import'
for f in conf.iterdir():
 if f.suffix=='.txt': f.write_text('')
(conf/'login_conf.txt').write_text('bind_ip: 127.0.0.1\nlogin_port: 16900\nnew_account: no\nipban: no\nconsole: no\n')
(conf/'char_conf.txt').write_text(f'userid: stage_internal\npasswd: {internal}\nlogin_ip: 127.0.0.1\nlogin_port: 16900\nchar_ip: 127.0.0.1\nbind_ip: 127.0.0.1\nchar_port: 16121\npincode_enabled: no\nconsole: no\n')
(conf/'map_conf.txt').write_text(f'userid: stage_internal\npasswd: {internal}\nchar_ip: 127.0.0.1\nchar_port: 16121\nmap_ip: 127.0.0.1\nbind_ip: 127.0.0.1\nmap_port: 15121\nconsole: no\n')
(conf/'inter_conf.txt').write_text(''.join(f'{k}: ragoff-stage\n' for k in ('login_server_db','char_server_db','map_server_db','ipban_db_db','log_db_db')))
(conf/'battle_conf.txt').write_text(('companion_enable: 0\n' if mode != 'baseline' else ''))
# Dedicated test-only group with commands. Does not alter production permissions.
(conf/'groups.yml').write_text('Header:\n  Type: PLAYER_GROUP_DB\n  Version: 1\nBody:\n  - Id: 99\n    Name: StagingTester\n    Level: 99\n    Permissions:\n      all_commands: true\n      can_party: true\n      can_trade: true\n')
db=sqlite3.connect(out/'ragoff-stage.sqlite3')
for name in ('main.sql','logs.sql','web.sql'):
 db.executescript('\n'.join(line for line in (root/'sqlite-files'/name).read_text().splitlines() if not line.lstrip().startswith('#')))
# Apply shipped SQLite upgrades in order; main.sql already includes some ADD COLUMNs.
for upgrade in sorted((root/'sqlite-files/upgrades').glob('*.sql')):
 statement = ''
 for line in upgrade.read_text().splitlines():
  statement += line + '\n'
  if sqlite3.complete_statement(statement):
   try: db.executescript(statement)
   except sqlite3.OperationalError as e:
    if 'duplicate column name:' not in str(e): raise
   statement = ''
db.execute('UPDATE login SET userid=?,user_pass=? WHERE account_id=1',('stage_internal',internal))
db.execute("INSERT INTO login (account_id,userid,user_pass,sex,email,group_id) VALUES (2000001,?,?, 'M','stage@localhost',99)",('stage_owner',player))
db.execute("INSERT INTO char (char_id,account_id,char_num,name,class,base_level,job_level,last_map,last_x,last_y,save_map,save_x,save_y,hp,max_hp,sp,max_sp,sex) VALUES (150001,2000001,0,'StageOwner',0,10,10,'prontera',150,180,'prontera',150,180,100,100,50,50,'M')")
if mode.startswith(('m3','m4','m5','m6','m7','m8','m9')):
 peer=secrets.token_hex(10)
 db.execute("INSERT INTO login (account_id,userid,user_pass,sex,email,group_id) VALUES (2000002,?,?, 'F','peer@localhost',99)",('stage_peer',peer))
 db.execute("INSERT INTO char (char_id,account_id,char_num,name,class,base_level,job_level,last_map,last_x,last_y,save_map,save_x,save_y,hp,max_hp,sp,max_sp,sex) VALUES (150002,2000002,0,'StagePeer',0,10,10,'prontera',150,180,'prontera',150,180,100,100,50,50,'F')")
 (out/'peer-fixture.json').write_text(json.dumps({'username':'stage_peer','password':peer,'name':'StagePeer','account_id':2000002,'char_id':150002}))
 (out/'peer-fixture.json').chmod(0o600)
if mode.startswith(('m6','m7','m8','m9')):
 db.executescript((root/'sqlite-files/companion/001_profiles.sql').read_text())
 if mode.startswith(('m7','m8','m9')): db.executescript((root/'sqlite-files/companion/002_policy.sql').read_text())
 if mode.startswith(('m8','m9')): db.executescript((root/'sqlite-files/companion/003_gear.sql').read_text())
 with (conf/'groups.yml').open('a') as f:f.write('  - Id: 0\n    Commands:\n      companion: true\n')
 with (out/'npc/scripts_custom.conf').open('a') as f:f.write('\nnpc: npc/custom/companion_recruiter.txt\n')
if mode.startswith(('m8','m9')):
 db.executescript((root/'sqlite-files/companion/007_gear_details.sql').read_text())
if mode.startswith('m8'):
 (out/'db/import/mob_db.yml').write_text('Header:\n  Type: MOB_DB\n  Version: 5\nBody:\n  - Id: 1008\n    Hp: 500\n')
if mode.startswith('m9'):
 db.executescript((root/'sqlite-files/companion/004_owner_progression.sql').read_text())
 (out/'M9_TEST').touch()
 if mode!='m9off':(out/'db/import/mob_db.yml').write_text(f'Header:\n  Type: MOB_DB\n  Version: 5\nBody:\n  - Id: 1008\n    Hp: {5000 if mode.startswith("m92") else 500}\n    Defense: 0\n')
 if mode.startswith('m93'):
  db.executescript((root/'sqlite-files/companion/005_supplies.sql').read_text())
  with (conf/'battle_conf.txt').open('a') as f:f.write('companion_supplies: 1\n')
 if mode.startswith(('m92','m93')) and mode!='m92off':
  db.executescript((root/'sqlite-files/companion/006_presets.sql').read_text())
  with (conf/'battle_conf.txt').open('a') as f:f.write('companion_loadouts: 1\n')
 if mode.startswith('m93'):
  db.executescript((root/'sqlite-files/companion/008_hunter.sql').read_text())
 if mode!='m9off':
  with (conf/'battle_conf.txt').open('a') as f:f.write('companion_owner_progression: 1\n')
db.commit();db.close()
(out/'fixture.json').write_text(json.dumps({'username':'stage_owner','password':player,'account_id':2000001,'char_id':150001}))
(out/'fixture.json').chmod(0o600)
(out/'STAGING_ONLY').write_text('Fresh database. Run only with docker --network none. No production mounts.\n')
(root/'artifacts'/f'{mode}-binaries.json').write_text(json.dumps({n:hashlib.sha256((out/n).read_bytes()).hexdigest() for n in ('login-server','char-server','map-server')},indent=2))
print(out)

# Focused instrumented M9 run: skip unrelated random-box/enchantment recipes.
# Keep complete native item/skill/job/mob records for the tested combat/equipment paths.
if mode in ('m9asan','m92asan','m93asan'):
 for filename in ('item_group_db.yml','item_combos.yml','item_enchant.yml','item_reform.yml','item_randomopt_group.yml'):
  p=out/'db/re'/filename
  header=p.read_text().split('Body:',1)[0]
  p.write_text(header+'Body: []\n')

# Focused M9.3 memory suite needs native items/skills/maps and the recruiter, not world quest NPCs.
if mode=="m93asan":
 (out/"npc/re/scripts_main.conf").write_text("npc: npc/custom/companion_recruiter.txt\n")
