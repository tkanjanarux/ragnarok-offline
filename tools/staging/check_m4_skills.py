"""Real native skill packets and party sharing eligibility (isolated test runtime only)."""
import pathlib,time,struct,re,socket
from protocol import entry

def wait(c,predicate,timeout=25):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  try:i,b=c.packet()
  except socket.timeout:continue
  if predicate(i,b):return b
 raise AssertionError('expected skill/state packet missing')

def summon(c,job):
 jobs={'knight':7,'priest':8,'wizard':9}
 c.command('@companion add '+job)
 b=wait(c,lambda i,b:i in (0x9fe,0x9ff) and 95000000<=struct.unpack_from('<I',b,5)[0]<100000000 and struct.unpack_from('<H',b,23)[0]==jobs[job])
 return struct.unpack_from('<I',b,5)[0]

def state(c,aid):
 c.command('@companion status')
 b=wait(c,lambda i,b:i==0x8e and ('Companion id='+str(aid)+' ').encode() in b)
 return {k:int(v) for k,v in re.findall(r'(id|party|assist|hp|target|sp|class|exp|share)=(\d+)',b.decode(errors='replace'))}

def skill(c,aid,skid,target=2000001):
 return wait(c,lambda i,b:i==0x9cb and struct.unpack_from('<H',b,2)[0]==skid and struct.unpack_from('<II',b,8)==(target,aid) and b[16]==1)

def dismiss_all(c,ids,text):
 c.command('@companion dismiss');text(c,'Companion dismissed.')
 end=time.monotonic()+10
 while time.monotonic()<end:
  log=pathlib.Path('/stage/artifacts/map-server.log').read_text()
  if all(f'released id={aid} detached=1 timers_clear=1' in log for aid in ids):return
  time.sleep(.1)
 raise AssertionError('multi-companion cleanup missing')

def verify_skills(c,text):
 c.command('@heal');time.sleep(.2)
 priest=summon(c,'priest')
 before=state(c,priest)['sp']
 c.command('@set Hp 1')
 c.command('@companion assist')
 heal=skill(c,priest,28)
 assert struct.unpack_from('<i',heal,4)[0]>0
 after=state(c,priest)['sp'];assert after<before,(before,after)
 c.command(f'#heal Companion{priest}')
 skill(c,priest,34)
 c.command(f'#heal Companion{priest}')
 skill(c,priest,29)
 c.command(f'#heal Companion{priest}')
 c.command('@die')
 revived = False
 end = time.monotonic()+25
 while time.monotonic()<end:
  i,b=c.packet()
  if i==0x148 and struct.unpack_from('<I',b,2)[0]==2000001:revived=True
  if i==0x9cb and struct.unpack_from('<H',b,2)[0]==54 and struct.unpack_from('<II',b,8)==(2000001,priest):
   assert revived and b[16]==1;break
 else:raise AssertionError('native resurrection missing')
 result={'priest_native_heal':True,'priest_native_buffs':True,'priest_native_resurrection':True,'native_sp_cost':before-after}
 # Synthetic inventory is finite and normal resurrection consumes its reagent.
 c.command('@companion stop');text(c,'Companion stopped.')
 c.command('@set Hp 1')
 end=time.monotonic()+2;c.s.settimeout(.2)
 while time.monotonic()<end:
  try:i,b=c.packet()
  except socket.timeout:continue
  assert not (i==0x9cb and struct.unpack_from('<H',b,2)[0]==28 and struct.unpack_from('<I',b,12)[0]==priest)
 c.s.settimeout(10)
 result['stop_suppresses_support']=True
 c.command('@heal')
 knight=summon(c,'knight');wizard=summon(c,'wizard')
 # Full party roster must include all three, with normal identity fields.
 wait(c,lambda i,b:i==0xae5 and all(struct.pack('<II',a,a) in b for a in (priest,knight,wizard)))
 fourth=summon(c,'knight')
 c.command('@companion add knight');text(c,'Maximum four companions')
 result['four_actor_cap']=True
 c.send(struct.pack('<HI',0x102,1));time.sleep(.5)
 assert state(c,priest)['share']==1
 c.command('@baselevel 20');time.sleep(.5)
 assert state(c,priest)['share']==0,'fake member omitted from share level bounds'
 c.command('@baselevel -20');time.sleep(.5)
 c.send(struct.pack('<HI',0x102,1));time.sleep(.5)
 assert state(c,priest)['share']==1
 result['synthetic_level_share_gate']=True
 dismiss_all(c,[priest,knight,wizard,fourth],text)
 # Exercise each offensive skill separately so one companion cannot steal the test target.
 for job,skid in [('knight',5),('wizard',19)]:
  profile=None
  if pathlib.Path('/stage/M7_TEST').exists():
   from check_m6_profiles import api
   before={r['id'] for r in api(c,'list')[0]}
   row=next(r for r in api(c,'recruit '+job)[0] if r['id'] not in before)
   profile=row['id']
   api(c,f"skills {profile} "+('bash' if job=='knight' else 'firebolt'))
   aid=next(r['actor'] for r in api(c,f'summon {profile}')[0] if r['id']==profile)
  else:aid=summon(c,job)
  time.sleep(.5)
  c.command('@companion assist');text(c,'Companion assisting')
  c.command('@monster 1008 1')
  b=wait(c,lambda i,b:i in (0x9fe,0x9ff) and struct.unpack_from('<H',b,23)[0]==1008)
  mob=struct.unpack_from('<I',b,5)[0]
  from check_m3_combat import move_to_spawn
  move_to_spawn(c,b)
  ident,e=entry('clif_parse_ActionRequest');c.send(struct.pack('<HIB',ident,mob,7))
  b=wait(c,lambda i,b:i==0x1de and struct.unpack_from('<HII',b,2)==(skid,aid,mob))
  assert struct.unpack_from('<i',b,24)[0]>0,b.hex()
  wait(c,lambda i,b:i==0x80 and struct.unpack_from('<I',b,2)[0]==mob and b[6]==1)
  result[job+'_native_skill_damage_and_death']=True
  ident,_=entry('clif_parse_StopAttack');c.send(struct.pack('<H',ident))
  dismiss_all(c,[aid],text)
  if profile:api(c,f'retire {profile} confirm')
 return result
