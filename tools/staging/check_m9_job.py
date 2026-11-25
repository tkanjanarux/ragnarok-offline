"""Direct owner Job synchronization, independent Base, cap/reset/resource preservation."""
import pathlib,time,json
from protocol import login
from check_m6_profiles import api
R=pathlib.Path('/stage');assert (R/'M9_TEST').exists()
c=login();c.command('@setbattleflag companion_enable 1');c.command('@jobchange 4054');c.command('@allskill');c.command('@set BaseLevel 30');c.command('@set JobLevel 20');c.command('@setbattleflag natural_healhp_interval 3600000');c.command('@setbattleflag natural_healsp_interval 3600000');time.sleep(.8)
for job in ('knight','priest','wizard'):api(c,'recruit '+job)
rows=api(c,'list')[0];assert len(rows)==3
for r in rows:assert r['level']==30 and r['job_level']==20,r;api(c,f'summon {r["id"]}');api(c,f'stop {r["id"]}')
for r in api(c,'list')[0]:c.command(f'#set {r["name"]} Hp {r["max_hp"]//2}');c.command(f'#set {r["name"]} Sp {r["max_sp"]//2}')
before=api(c,'list')[0];c.command('@set JobLevel 35');time.sleep(.8);after=api(c,'list')[0]
for a,b in zip(before,after):
 assert b['level']==30 and b['job_level']==35
 assert b['hp']==max(1,a['hp']*b['max_hp']//a['max_hp']) and b['sp']==a['sp']*b['max_sp']//a['max_sp'],(a,b)
c.command('@set BaseLevel 60');time.sleep(.8);assert all(r['level']==60 and r['job_level']==35 for r in api(c,'list')[0])
c.command('@set JobLevel 70');time.sleep(.8);assert all(r['job_level']==50 for r in api(c,'list')[0])
c.command('@set JobLevel 1');time.sleep(.8);assert all(r['job_level']==1 for r in api(c,'list')[0])
for r in rows:api(c,f'bench {r["id"]}')
c.command('@set JobLevel 42');time.sleep(.8);assert all(r['job_level']==42 for r in api(c,'list')[0])
for r in rows:api(c,f'summon {r["id"]}')
assert all(r['job_level']==42 and r['level']==60 and r['exp']==r['job_exp']==0 for r in api(c,'list')[0])
c.close();time.sleep(1)
result=dict(three_jobs_direct_sync=True,job_only_change_preserves_hp_sp_fraction=True,base_independent=True,job70_capped50=True,job_reset_to1=True,reserved_preview_and_resummon=True,ai_exp_zero=True)
(R/'artifacts/m9-job-results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
