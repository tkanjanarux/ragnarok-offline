"""M7 real protocol / native cast priority tests; disposable fixtures only."""
import pathlib,sqlite3,time,re,struct
from check_m4_skills import wait
from protocol import login
from check_m6_profiles import api
ROOT=pathlib.Path('/stage');assert (ROOT/'M7_TEST').exists()
def verify_policy(c,text):
 rows,_,_=api(c,'list');knight=next(r for r in rows if r['job']==7);priest=next(r for r in rows if r['job']==8);kid=knight['id'];pid=priest['id']
 assert 'role=tank skills=provoke,endure,quicken,pierce,spearboomerang,bowlingbash,bash' in api(c,f'config {kid}')[1]
 assert 'role=dps' in api(c,f'role {kid} dps')[1]
 assert 'skills=bash' in api(c,f'skills {kid} bash')[1]
 for verb,arg in [('role','tank'),('skills','bash'),('skills','heal,heal'),('skills','heal,')]:
  assert 'Invalid' in api(c,f'{verb} {pid} {arg}')[1]
 peer=login('/stage/peer-fixture.json');assert 'not found' in api(peer,f'role {kid} tank')[1];peer.close()
 # A failed write must not change the stored/live policy.
 db=sqlite3.connect(ROOT/'ragoff-stage.sqlite3');db.execute("CREATE TRIGGER m7_fail_policy BEFORE UPDATE ON ragoff_companion_policy BEGIN SELECT RAISE(FAIL,'M7 injected settings failure'); END");db.commit();db.close()
 assert 'save failed' in api(c,f'role {kid} tank')[1]
 assert 'role=dps skills=bash' in api(c,f'config {kid}')[1]
 db=sqlite3.connect(ROOT/'ragoff-stage.sqlite3');db.execute('DROP TRIGGER m7_fail_policy');db.commit();db.close()
 # Corrupt/incompatible stored settings fail closed, before actor allocation.
 db=sqlite3.connect(ROOT/'ragoff-stage.sqlite3');db.execute("INSERT INTO ragoff_companion_policy VALUES(?,'dps','heal')",(pid,));db.commit();db.close()
 rows,note,_=api(c,f'summon {pid}');assert 'Summon failed' in note and next(r for r in rows if r['id']==pid)['actor']==0
 db=sqlite3.connect(ROOT/'ragoff-stage.sqlite3');db.execute('DELETE FROM ragoff_companion_policy WHERE profile_id=?',(pid,));db.commit();db.close()
 # Disable all priest skills and prove assist does not cast on a hurt owner.
 api(c,f'skills {pid} none');rows,_,_=api(c,f'summon {pid}');aid=next(r['actor'] for r in rows if r['id']==pid)
 c.command('@heal');c.command(f'#heal {priest["name"]}');c.command('@set Hp 1')
 log=ROOT/'artifacts/map-server.log';offset=len(log.read_text())
 api(c,f'assist {pid}');time.sleep(3)
 assert f'cast id={aid} ' not in log.read_text()[offset:]
 api(c,f'stop {pid}')
 # With both an injured owner and a corpse, explicit heal-first precedes resurrection.
 rows,_,_=api(c,f'summon {kid}');kaid=next(r['actor'] for r in rows if r['id']==kid)
 c.command(f'#kill {knight["name"]}');c.command(f'#heal {priest["name"]}');c.command('@set Hp 1')
 api(c,f'skills {pid} heal,resurrection');offset=len(log.read_text())
 api(c,f'assist {pid}');time.sleep(7)
 casts=re.findall(rf'cast id={aid} skill=(\d+) target=(\d+)',log.read_text()[offset:])
 assert casts and casts[0]==('28','2000001'),casts
 assert ('54',str(kaid)) in casts,casts
 api(c,f'bench {pid}');api(c,f'bench {kid}');c.command('@heal')
 # DPS does not acquire a party threat on its own; Tank immediately protects it.
 c.command('@baselevel 40');c.command('@heal');c.command('@killmonster2')
 api(c,f'skills {kid} provoke,bash');c.command('@monster 1054 1')
 b=wait(c,lambda i,b:i in (0x9fe,0x9ff) and struct.unpack_from('<H',b,23)[0]==1054);mob=struct.unpack_from('<I',b,5)[0]
 wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(mob,2000001))
 rows,_,_=api(c,f'summon {kid}');kaid=next(r['actor'] for r in rows if r['id']==kid)
 c.command(f'#baselevel {knight["name"]} 40');c.command(f'#heal {knight["name"]}')
 api(c,f'assist {kid}');offset=len(log.read_text());time.sleep(2)
 assert f'cast id={kaid} ' not in log.read_text()[offset:]
 api(c,f'role {kid} tank')
 wait(c,lambda i,b:i==0x9cb and struct.unpack_from('<H',b,2)[0]==6 and struct.unpack_from('<II',b,8)==(mob,kaid))
 wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(mob,kaid))
 c.command('@killmonster2');c.command(f'#baselevel {knight["name"]} -40');c.command('@baselevel -40');c.command('@heal')
 api(c,f'bench {kid}');api(c,f'role {kid} dps');api(c,f'skills {kid} bash')
 # Custom config survives a new actor identity and owner reconnect.
 assert 'role=dps skills=bash' in api(c,f'config {kid}')[1]
 c.close();time.sleep(5);c=login()
 assert 'skills=heal,resurrection' in api(c,f'config {pid}')[1]
 assert 'role=dps skills=bash' in api(c,f'config {kid}')[1]
 # Deleting a profile cleans settings; no orphan settings rows.
 rows,_,_=api(c,'recruit wizard');wid=next(r['id'] for r in rows if r['job']==9)
 api(c,f'skills {wid} none');api(c,f'retire {wid} confirm')
 db=sqlite3.connect('file:/stage/ragoff-stage.sqlite3?mode=ro',uri=True)
 assert db.execute('SELECT count(*) FROM ragoff_companion_policy WHERE profile_id=?',(wid,)).fetchone()[0]==0;db.close()
 return c,{'policy_validation_and_owner_isolation':True,'policy_failed_write_atomic':True,'policy_none_suppresses_native_casts':True,'policy_heal_before_resurrection_native_casts':True,'policy_logout_persistence':True,'policy_release_cleanup':True,'policy_corrupt_storage_rejected':True,'policy_live_tank_vs_dps_targeting':True}
