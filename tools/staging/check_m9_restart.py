"""Post-shutdown restart: saved HP/SP/caps and equipment unique IDs survive."""
import pathlib,json,sqlite3,time
from protocol import login
from check_m6_profiles import api
from check_m8_gear import held,conserved
R=pathlib.Path('/stage');assert (R/'M9_TEST').exists()
with sqlite3.connect('file:/stage/ragoff-stage.sqlite3?mode=ro',uri=True) as d:
 expected=d.execute('SELECT r.id,r.hp,r.sp,g.max_hp,g.max_sp FROM ragoff_companion r JOIN ragoff_companion_growth g ON g.profile_id=r.id ORDER BY r.id').fetchall()
c=login();c.command('@setbattleflag companion_enable 1');c.command('@setbattleflag natural_healhp_interval 3600000');c.command('@setbattleflag natural_healsp_interval 3600000');seen=[]
for pid,hp,sp,mhp,msp in expected:
 rr,note,_=api(c,f'summon {pid}');r=next(r for r in rr if r['id']==pid)
 assert (r['hp'],r['sp'],r['max_hp'],r['max_sp'])==(hp,sp,mhp,msp),(pid,r,(hp,sp,mhp,msp))
 for gid,uid,equip,state in held(pid):conserved(uid)
 seen.append(pid);api(c,f'bench {pid}')
c.close();result={'profiles_preserve_exact_resources_after_restart':seen,'gear_unique_ids_conserved':True};(R/'artifacts/m9-restart-results.json').write_text(json.dumps(result));print(json.dumps(result))
