"""M9.1 integration using the real protocol; disposable network-none fixtures only."""
import pathlib,json,time,struct,re,sqlite3
from protocol import login,entry
from check_m6_profiles import api
from check_m4_skills import wait,state,summon,dismiss_all
from check_m4_exp import drain,warp
ROOT=pathlib.Path('/stage');assert (ROOT/'M9_TEST').exists()
result={}
def row(c,pid):return next(r for r in api(c,'list')[0] if r['id']==pid)
def stats(c,aid):
 c.command('@companion status');b=wait(c,lambda i,b:i==0x8e and f'Companion id={aid} '.encode() in b)
 return {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',b.decode(errors='replace'))}
def text(c,needle):return wait(c,lambda i,b:i==0x8e and needle.encode() in b)
def level(c,n):c.command('@set BaseLevel '+str(n));time.sleep(.8)
def db(sql):
 with sqlite3.connect(ROOT/'ragoff-stage.sqlite3') as d:return d.execute(sql).fetchall()
c=login();c.command('@setbattleflag companion_enable 1');c.command('@allskill');level(c,30)
c.command('@setbattleflag natural_healhp_interval 3600000');c.command('@setbattleflag natural_healsp_interval 3600000')
warp(c,'prontera 100 100')
ids=[]
for job in ('knight','priest','wizard'):
 before={r['id'] for r in api(c,'list')[0]};rr=api(c,'recruit '+job)[0];pid=next(r['id'] for r in rr if r['id'] not in before);ids.append(pid)
 assert row(c,pid)['level']==30
 api(c,f'summon {pid}');api(c,f'stop {pid}')
 r=row(c,pid);assert r['level']==30 and r['job_level']==10 and r['exp']==r['job_exp']==0,r
 s=stats(c,r['actor']);assert s['growth']==1 and all(1<=s[k]<=99 for k in ('str','agi','vit','int','dex','luk')),s
result['three_jobs_owner_level_and_native_stat_bounds']=True
for pid in ids:
 r=row(c,pid);c.command(f'#set {r["name"]} Hp {r["max_hp"]//2}');c.command(f'#set {r["name"]} Sp {r["max_sp"]//2}')
before=[row(c,pid) for pid in ids];level(c,50)
after=[row(c,pid) for pid in ids]
for a,b in zip(before,after):
 assert b['level']==50 and b['job_level']==10,(a,b)
 assert b['hp']==a['hp']*b['max_hp']//a['max_hp'] and b['sp']==a['sp']*b['max_sp']//a['max_sp'],(a,b)
level(c,10)
for a,pid in zip(after,ids):
 b=row(c,pid);assert b['level']==10 and b['job_level']==10
 assert b['hp']==max(1,a['hp']*b['max_hp']//a['max_hp']) and b['sp']==a['sp']*b['max_sp']//a['max_sp'],(a,b)
result['live_level_up_down_preserves_resource_fraction']=True
kid=ids[0];r=row(c,kid)
# Keep owner away from savepoint; native recovery should not resurrect here.
c.command(f'#kill {r["name"]}');time.sleep(.2);level(c,20)
assert row(c,kid)['hp']==0
api(c,f'bench {kid}');api(c,f'summon {kid}');assert row(c,kid)['hp']==0
result['dead_stays_dead_across_sync_and_resummon']=True
# Use living Wizard to prove no cumulative rounding/healing in 100 cycles.
pid=ids[2];before=row(c,pid);seen=set()
for n in range(100):
 api(c,f'bench {pid}');api(c,f'summon {pid}');api(c,f'stop {pid}');r=row(c,pid)
 assert r['actor'] not in seen;seen.add(r['actor'])
 assert (r['hp'],r['sp'],r['max_hp'],r['max_sp'])==(before['hp'],before['sp'],before['max_hp'],before['max_sp']),(n,before,r)
result['resource_stable_summon_cycles']=len(seen)
# Save both profile and cap metadata in one transaction.
with sqlite3.connect(ROOT/'ragoff-stage.sqlite3') as d:d.execute("CREATE TRIGGER m9_fail_caps BEFORE UPDATE ON ragoff_companion_growth BEGIN SELECT RAISE(FAIL,'M9 injected cap failure'); END")
old=db(f'SELECT level,hp,sp FROM ragoff_companion WHERE id={pid}')
rr,note,_=api(c,f'bench {pid}');assert 'Save failed' in note and row(c,pid)['actor']
assert db(f'SELECT level,hp,sp FROM ragoff_companion WHERE id={pid}')==old
with sqlite3.connect(ROOT/'ragoff-stage.sqlite3') as d:d.execute('DROP TRIGGER m9_fail_caps')
result['profile_cap_transaction_failure_is_atomic']=True
for pid in ids:api(c,f'bench {pid}')
level(c,60)
assert all(r['level']==60 and r['job_level']==10 and r['exp']==r['job_exp']==0 for r in api(c,'list')[0])
result['reserved_roster_follows_owner_without_spawn']=True
# Owner logout is a real socket close, and must checkpoint and release all actors.
for pid in ids:api(c,f'summon {pid}');api(c,f'stop {pid}')
aids=[r['actor'] for r in api(c,'list')[0]];c.close();time.sleep(2)
log=(ROOT/'artifacts/map-server.log').read_text()
assert all(f'released id={a} detached=1 timers_clear=1' in log for a in aids)
c=login();assert all(r['actor']==0 for r in api(c,'list')[0]);result['owner_logout_cleanup_and_profile_reload']=True
# Restore a simple living state for equipment and EXP tests.
for pid in ids:
 api(c,f'summon {pid}');c.command('#heal '+row(c,pid)['name']);api(c,f'bench {pid}')
(ROOT/'artifacts/m9-progression-results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
c.close()
