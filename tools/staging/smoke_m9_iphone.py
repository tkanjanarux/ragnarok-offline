"""Existing Staging owner's roster via ordinary packets; no grants/warps/equipment transfers."""
import pathlib,time,struct,re,json,sqlite3
from protocol import login
from check_m6_profiles import api
R=pathlib.Path('/stage');assert (R/'STAGING_ONLY').exists() and not (R/'M9_TEST').exists()
c=login();seen=set();original=c.packet
def packet():
 i,b=original()
 if i in (0x9fe,0x9ff):
  aid=struct.unpack_from('<I',b,5)[0]
  if 95000000<=aid<100000000:seen.add(aid)
 return i,b
c.packet=packet
rows,note,on=api(c,'list');assert on and len(rows)==3 and not any(r['actor'] for r in rows)
with sqlite3.connect('file:/stage/ragoff-stage.sqlite3?mode=ro',uri=True) as db:
 base=db.execute('SELECT base_level FROM char WHERE char_id=?',(json.loads((R/'fixture.json').read_text())['char_id'],)).fetchone()[0]
assert all(r['level']==min(base,99) and r['exp']==r['job_exp']==0 for r in rows)
kid=next(r['id'] for r in rows if r['job']==7)
rr,note,_=api(c,f'summon {kid}');active=next(r for r in rr if r['id']==kid);aid=active['actor'];assert aid and aid in seen
assert active['level']==min(base,99)
api(c,f'bench {kid}');assert not any(r['actor'] for r in api(c,'list')[0]);c.close();time.sleep(.5)
log=(R/'artifacts/map-server.log').read_text(errors='replace');assert f'released id={aid} detached=1 timers_clear=1' in log
assert re.search(rf'spawned id={aid} .*fd=-1',log)
result=dict(staging_server_smoke='PASS',native_iphone='UNVERIFIED',owner_base_level=base,roster_profiles=3,companion_base_level=active['level'],companion_job_level=active['job_level'],standard_spawn_packet=True,no_client_socket=True,summon_reserve_cleanup=True,items_or_cash_granted=False)
(R/'artifacts/m9-staging-smoke.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
