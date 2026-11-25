"""Curated skill gates, native casts and loaned-equipment conservation, disposable only."""
import pathlib,json,time,struct,re,socket,sqlite3
from protocol import login,entry
from check_m6_profiles import api
from check_m4_skills import wait,skill
from check_m4_exp import warp,drain
from check_m8_gear import verify_gear,held,transfer,slot,returned,query
R=pathlib.Path('/stage');assert (R/'M9_TEST').exists()
def text(c,s):return wait(c,lambda i,b:i==0x8e and s.encode() in b)
def rows(c):return api(c,'list')[0]
def row(c,pid):return next(r for r in rows(c) if r['id']==pid)
def info(c,pid):
 aid=row(c,pid)['actor'];c.command('@companion status')
 b=wait(c,lambda i,b:i==0x8e and f'Companion loadout id={aid} '.encode() in b)
 return {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',b[4:].decode(errors='replace'))}
c=login();c.command('@setbattleflag companion_enable 1');c.command('@jobchange 4054');c.command('@allskill');c.command('@set BaseLevel 30');c.command('@set JobLevel 1');c.command('@setbattleflag natural_healhp_interval 3600000');c.command('@setbattleflag natural_healsp_interval 3600000')
warp(c,'prontera 150 180');api(c,'party');time.sleep(.5)
for old in rows(c):
 api(c,f'bench {old["id"]}');api(c,f'retire {old["id"]} confirm')
for j in ('knight','priest','wizard'):api(c,'recruit '+j)
profiles=rows(c);kid=next(r['id'] for r in profiles if r['job']==7);pid=next(r['id'] for r in profiles if r['job']==8);wid=next(r['id'] for r in profiles if r['job']==9)
for r in profiles:api(c,f'summon {r["id"]}');api(c,f'stop {r["id"]}')
assert all(info(c,r['id'])['starter_count']==2 and info(c,r['id'])['starter_equipped']==2 for r in profiles)
assert not query('SELECT id FROM ragoff_companion_gear')
assert 'loaned' in api(c,f'equipment {kid}')[1]
expected={1:(1,0,0),5:(1,1,0),6:(2,1,0),19:(4,3,0),20:(4,4,1),30:(6,6,2),50:(10,10,4)}
for jl,(main,buff,res) in expected.items():
 c.command('@set JobLevel '+str(jl));time.sleep(.8)
 k,p,w=info(c,kid),info(c,pid),info(c,wid)
 assert (k['skill5'],k['skill6'])==(main,buff),(jl,k)
 assert (p['skill28'],p['skill34'],p['skill29'],p['skill54'])==(main,buff,buff,res),(jl,p)
 assert w['skill19']==main,(jl,w)
 assert all(r['job_level']==jl and r['level']==30 for r in rows(c))
c.command('@set JobLevel 1');time.sleep(.8);assert info(c,pid)['skill54']==info(c,pid)['skill34']==0
result={'job_thresholds_and_native_caps':list(expected),'job_reset_removes_locked_skills':True,'two_loan_items_each_no_escrow_rows':True,'equipment_ui_description':True}
# Normal native support. Locked resurrection may not consume a reagent.
api(c,f'assist {pid}');p=row(c,pid);c.command('#heal '+p['name']);c.command('@set Hp 1');skill(c,p['actor'],28)
c.command('@die');start=row(c,pid)['gems'];end=time.monotonic()+3
c.s.settimeout(.2)
while time.monotonic()<end:
 try:i,b=c.packet()
 except socket.timeout:continue
 assert not (i==0x9cb and struct.unpack_from('<H',b,2)[0]==54),'locked resurrection cast'
c.s.settimeout(10);assert row(c,pid)['gems']==start
c.command('@alive');c.command('@set JobLevel 20');time.sleep(.8);c.command('#heal '+p['name']);c.command('@die');skill(c,p['actor'],54)
assert row(c,pid)['gems']==start-1
api(c,f'stop {pid}');result.update(native_heal=True,resurrection_locked_below_job20=True,native_resurrection_and_reagent=True)
# Native Fire Bolt's actual packet reports the selected skill level (not just stored skill data).
c.command('@jobchange 2');c.command('@allskill');c.command('@heal');time.sleep(1)
for jl,lv in ((1,1),(26,6)):
 c.command('@set JobLevel '+str(jl));time.sleep(.8);api(c,f'assist {wid}');w=row(c,wid);c.command('#heal '+w['name']);c.command('@heal');c.command('@killmonster2')
 c.command('@monster 1008 1');b=wait(c,lambda i,b:i in (0x9fe,0x9ff) and struct.unpack_from('<H',b,23)[0]==1008);mob=struct.unpack_from('<I',b,5)[0]
 # Ranged Fire Bolt does not require a warp; warping clears the assist target/state.
 ident,_=entry('clif_parse_UseSkillToId');c.send(struct.pack('<HHHI',ident,1,19,mob))
 # Retry the native owner opener after its after-cast delay (wire client has no input queue).
 end=time.monotonic()+40;retry=0;b=None;c.s.settimeout(.2)
 while time.monotonic()<end:
  if time.monotonic()>=retry:
   c.send(struct.pack('<HHHI',ident,1,19,mob));retry=time.monotonic()+3
  try:i,packet=c.packet()
  except socket.timeout:continue
  if i==0x1de and struct.unpack_from('<HII',packet,2)==(19,w['actor'],mob):b=packet;break
 c.s.settimeout(10);assert b is not None,('native Fire Bolt missing',jl,w['actor'],mob)
 assert struct.unpack_from('<h',b,28)[0]==lv,(jl,b.hex())
 api(c,f'stop {wid}');c.command('@killmonster2')
result['native_firebolt_levels_1_and_6']=True
# No starter item can be selected through the real equipment escrow API.
assert 'not found' in api(c,f'equip {kid} 0')[1]
warp(c,'izlude 120 110')
time.sleep(1.5)
for r in profiles:
 note=api(c,f'bench {r["id"]}')[1]
 assert 'reserve' in note.lower(), note
assert not query('SELECT id FROM ragoff_companion_gear') and not query('SELECT id FROM inventory WHERE char_id=150001')
# Repeated summon must not accumulate loaned items or heal the companion.
api(c,f'summon {kid}');api(c,f'stop {kid}');k=row(c,kid);c.command(f'#set {k["name"]} Hp 5');c.command(f'#set {k["name"]} Sp 1');before=row(c,kid)
for _ in range(100):
 api(c,f'bench {kid}');api(c,f'summon {kid}');api(c,f'stop {kid}');k=row(c,kid)
 assert info(c,kid)['starter_count']==2
 assert (k['hp'],k['sp'])==(before['hp'],before['sp']),(before,k)
api(c,f'bench {kid}');assert not query('SELECT id FROM ragoff_companion_gear') and not query('SELECT id FROM inventory WHERE char_id=150001')
result.update(loan_summon_cycles=100,no_loan_accumulation_or_resource_refill=True,no_player_inventory_or_escrow_loans=True)
# M8 real equipment still overrides the loan and returns to its owner unchanged.
c.command('@set BaseLevel 40');c.command('@set JobLevel 20');time.sleep(.8)
c,gear=verify_gear(c,text);result.update(gear)
assert gear['gear_weapon_atk']==25
# The loaned Knife's ATK17 was the native fallback during the regression's unequip step.
result['custom_equipment_overrides_loan_and_fallback_restored']=True
c.close();(R/'artifacts/m92-results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
