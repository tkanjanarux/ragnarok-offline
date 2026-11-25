"""Live Staging: inspect native UI frames; no supplies/equipment/cash grants or transfers."""
import pathlib,json,time,struct,sqlite3
from protocol import login
from check_m6_profiles import api
R=pathlib.Path('/stage');assert (R/'STAGING_ONLY').exists() and not (R/'M9_TEST').exists()
c=login();frames=[];actors=set();orig=c.packet
def packet():
 i,b=orig()
 if i==0x8e and b'[RCO1]' in b:frames.append(b[4:].decode().rstrip('\0'))
 if i in (0x9fe,0x9ff):
  aid=struct.unpack_from('<I',b,5)[0]
  if 95000000<=aid<100000000:actors.add(aid)
 return i,b
c.packet=packet
rows,note,on=api(c,'list');assert on and rows and not any(r['actor'] for r in rows)
for r in rows:
 frames.clear();api(c,f'inspect {r["id"]}')
 assert any(' detailbegin ' in f and f.split()[-1]=='1' for f in frames)
 assert sum(' starter ' in f for f in frames)==2
 assert sum(' skill ' in f for f in frames)==(2 if r['job']==7 else 4 if r['job']==8 else 1)
 (R/f'artifacts/m93-live-details-{r["id"]}.json').write_text(json.dumps(frames))
kid=next(r['id'] for r in rows if r['job']==7);rr,_,_=api(c,f'summon {kid}');k=next(r for r in rr if r['id']==kid);assert k['actor'] in actors
frames.clear();api(c,f'inspect {kid}');assert sum(' starter ' in f and f.split()[-1]=='1' for f in frames)==2
api(c,f'bench {kid}');assert not any(r['actor'] for r in api(c,'list')[0]);c.close();time.sleep(.5)
log=(R/'artifacts/map-server.log').read_text(errors='replace');assert f'released id={k["actor"]} detached=1 timers_clear=1' in log
with sqlite3.connect('file:/stage/ragoff-stage.sqlite3?mode=ro',uri=True) as d:
 assert d.execute('SELECT count(*) FROM ragoff_companion_supply_journal').fetchone()[0]==0
 assert d.execute('SELECT count(*) FROM ragoff_companion_supply').fetchone()[0]==0
result=dict(staging_server_smoke='PASS',native_iphone='UNVERIFIED',profiles=len(rows),details_and_skill_frames=True,starter_equipped_frames=True,standard_spawn_packet=True,cleanup=True,items_cash_or_supplies_granted=False)
(R/'artifacts/m93-staging-smoke.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
