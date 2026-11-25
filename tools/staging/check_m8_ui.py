"""Actual equipment snapshot protocol and UI-selected identity tests; disposable only."""
import pathlib,json,time,sqlite3
from protocol import login
from check_m6_profiles import api
from check_m8_gear import verify_gear,pause_char,query
from check_m4_skills import wait
assert pathlib.Path('/stage/M8_TEST').exists()
sequence=100000
frames=[]
def equipment(c,pid):
 global sequence
 sequence+=1;c.command(f'@companion ui {sequence} equipment {pid}')
 snap={'gear':[],'bag':[],'frames':[]}
 while True:
  i,b=c.packet()
  if i!=0x8e:continue
  line=b[4:].rstrip(b'\0').decode();t=line.split()
  if t[:2]!=['[RCO1]',str(sequence)]:continue
  snap['frames'].append(line)
  if t[2]=='gearbegin':snap.update(profile=int(t[3]),count=int(t[4]),bag_count=int(t[5]),busy=bool(int(t[6])))
  elif t[2] in ('gear','bag'):snap[t[2]].append(tuple(map(int,t[3:])))
  elif t[2]=='end':
   snap['message']=' '.join(t[3:]);break
 if 'profile' in snap:assert len(snap['gear'])==snap['count'] and len(snap['bag'])==snap['bag_count']
 frames.extend(snap['frames']);return snap

def settled(c,pid):
 end=time.monotonic()+15
 while True:
  s=equipment(c,pid)
  if not s['busy']:return s
  assert time.monotonic()<end;time.sleep(.05)

c=login();c.command('@setbattleflag companion_enable 1');c.command('@baselevel 20');c.command('@allskill');time.sleep(.5)
kid=api(c,'recruit knight')[0][0]['id'];api(c,'recruit priest');c.command('@item 1101 1')
s=equipment(c,kid);assert len(s['bag'])==1 and not s['gear'];slot,item,uid=s['bag'][0]
assert 'Inventory changed' in api(c,f'giveui {kid} {slot}:{uid+1}')[1];assert len(equipment(c,kid)['bag'])==1
peer=login('/stage/peer-fixture.json');assert 'profile' not in equipment(peer,kid);peer.close()
time.sleep(1)  # Finish the peer logout transaction before pausing Char.
pause_char(True)
try:
 assert 'Waiting' in api(c,f'giveui {kid} {slot}:{uid}')[1]
 assert equipment(c,kid)['busy']
 note = api(c,f'giveui {kid} {slot}:{uid}')[1]
 assert 'already pending' in note, note
finally:pause_char(False)
s=settled(c,kid);assert 'Equipment given' in s['message'] and not s['bag'] and len(s['gear'])==1
gid=s['gear'][0][0];api(c,f'summon {kid}');api(c,f'stop {kid}');api(c,f'equip {kid} {gid}')
assert equipment(c,kid)['gear'][0][2]>0
api(c,f'unequip {kid} {gid}');assert equipment(c,kid)['gear'][0][2]==0
api(c,f'bench {kid}');api(c,f'take {kid} {gid}');s=settled(c,kid);assert len(s['bag'])==1
# Journal retirement can occur just after transfer completion.
for _ in range(20):
 s=equipment(c,kid)
 if not s['gear']:break
 time.sleep(.05)
assert not s['gear'] and s['bag'][0][2]==uid
# Save a real server transcript for the Swift parser contract test.
pathlib.Path('/stage/artifacts/ui-frames.json').write_text(json.dumps(frames))
c.command('@itemreset');time.sleep(.2)
def text(c,needle):return wait(c,lambda i,b:i==0x8e and needle.encode() in b)
c,result=verify_gear(c,text);c.close();time.sleep(1)
result.update(ui_snapshot_counts=True,ui_unique_instance_selection=True,ui_pending_double_tap_guard=True,ui_owner_isolation=True,ui_equip_mask_refresh=True,ui_async_transfer_completion=True)
pathlib.Path('/stage/artifacts/ui-results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
