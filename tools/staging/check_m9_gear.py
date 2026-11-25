"""Native level restriction + retained escrow instance, then full M8 equipment regression."""
import json,time,pathlib
from protocol import login
from check_m6_profiles import api
from check_m4_skills import wait
from check_m8_gear import slot,transfer,held,conserved,returned,verify_gear
R=pathlib.Path('/stage');assert (R/'M9_TEST').exists()
def row(c,p):return next(r for r in api(c,'list')[0] if r['id']==p)
def text(c,s):return wait(c,lambda i,b:i==0x8e and s.encode() in b)
c=login();c.command('@companion dismiss');text(c,'Companion dismissed');c.command('@set BaseLevel 40');time.sleep(.8)
kid=next(r['id'] for r in api(c,'list')[0] if r['job']==7)
c.command('@item 1149 1');transfer(c,kid,slot(c,1149));gid,uid,_,_=held(kid)[0]
api(c,f'summon {kid}');c.command('#alive '+row(c,kid)['name']);c.command('#heal '+row(c,kid)['name']);api(c,f'stop {kid}');assert 'equipped and saved' in api(c,f'equip {kid} {gid}')[1];assert held(kid)[0][2]
c.command('@set BaseLevel 10');time.sleep(.8);assert held(kid)[0][2]==0;conserved(uid)
assert 'Cannot equip' in api(c,f'equip {kid} {gid}')[1]
api(c,f'bench {kid}');transfer(c,kid,gid,False);returned(uid);c.command('@itemreset')
c.command('@setbattleflag companion_owner_progression 0');c.command('@set BaseLevel 60');time.sleep(.8)
assert row(c,kid)['level']==60 # startup latch cannot partially disable EXP routing
c.command('@setbattleflag companion_owner_progression 1');c.command('@set JobLevel 50');c.command('@set BaseLevel 99');time.sleep(.8)
api(c,f'summon {kid}');assert row(c,kid)['level']==99 and row(c,kid)['job_level']==50
api(c,f'bench {kid}');c.command('@jobchange 4054');c.command('@set JobLevel 70');c.command('@set BaseLevel 150');time.sleep(.8)
api(c,f'summon {kid}');assert row(c,kid)['level']==99 and row(c,kid)['job_level']==50
api(c,f'bench {kid}');c.command('@set JobLevel 1');c.command('@set BaseLevel 1');time.sleep(.8)
api(c,f'summon {kid}');assert row(c,kid)['level']==1 and row(c,kid)['job_level']==1
api(c,f'bench {kid}');c.command('@set BaseLevel 40');time.sleep(.8)
c,results=verify_gear(c,text)
results.update(level_requirement_auto_unequip_retains_uid=True,startup_flag_latch=True,base_job_caps_1_and_99=True,owner_above_companion_cap_safe=True)
c.close();(R/'artifacts/m9-gear-results.json').write_text(json.dumps(results,indent=2));print(json.dumps(results),flush=True)
