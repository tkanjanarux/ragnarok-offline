"""Compare native real-player EXP with 0/1/3 companions and party eligibility."""
import pathlib,time,struct,json,socket
from protocol import login,entry
import threading
def heartbeat(client):
 def run():
  while client.s.fileno()>=0:
   try:
    ident,e=entry("clif_parse_TickSend");b=bytearray(e["length"]);struct.pack_into("<H",b,0,ident);struct.pack_into("<I",b,e["offsets"][0],int(time.monotonic()*1000)&0xffffffff);client.send(b)
   except OSError:return
   time.sleep(5)
 threading.Thread(target=run,daemon=True).start()
from check_m6_profiles import api
from check_m4_skills import summon,state,wait,dismiss_all
from check_m4_exp import drain,warp
R=pathlib.Path('/stage');assert (R/'M9_TEST').exists()
def text(c,s):return wait(c,lambda i,b:i==0x8e and s.encode() in b)
c=login();heartbeat(c);c.command('@setbattleflag companion_enable 1');c.command('@jobchange 2');c.command('@allskill');c.command('@set BaseLevel 10');c.command('@set JobLevel 10');c.command('@heal');c.command('@companion dismiss');text(c,'Companion dismissed')
for stat,value in (('str',30),('agi',98),('dex',40),('int',10)):
 c.command(f'@{stat} -1000');c.command(f'@{stat} {value}')

warp(c,'prontera 150 180');c.command('@killmonster2');api(c,'party');time.sleep(.5)
c.command('@setbattleflag exp_bonus_attacker 100');c.command('@setbattleflag party_even_share_bonus 20')
peer=login('/stage/peer-fixture.json');heartbeat(peer);peer.command('@set BaseLevel 10');peer.command('@set JobLevel 10');peer.command('@allskill');peer.command('@heal')
c.send(struct.pack('<HI',0xfc,2000002));time.sleep(.3)
peer.s.settimeout(.2);end=time.monotonic()+1
while time.monotonic()<end:
 try:i,b=peer.packet()
 except socket.timeout:continue
 if i==0x2c6:peer.send(struct.pack('<HIB',0x2c7,struct.unpack_from('<I',b,2)[0],1))
peer.s.settimeout(10);time.sleep(.5);warp(peer,'prontera 50 50')
results=[]
for formula,case in ((1,'far'),(2,'far'),(2,'dead'),(2,'other_map'),(2,'offline')):
 if case=='dead':peer.command('@die');time.sleep(.2)
 elif case=='other_map':peer.command('@alive');warp(peer,'izlude 120 110')
 elif case=='offline':peer.close();time.sleep(1)
 c.command('@setbattleflag exp_calc_type '+str(formula))
 for share in ((0,1) if case=='far' else (1,)):
  baseline=None
  for n in ((0,1,3) if case=='far' else (0,3)):
   print('CASE',formula,share,n,flush=True)
   aids=[summon(c,'knight') for _ in range(n)];time.sleep(.5)
   if n:
    c.command('@companion skills off');text(c,'Companion skills disabled.')
    c.command('@companion assist');text(c,'Companion assisting')
   c.send(struct.pack('<HI',0x102,share));time.sleep(.3);print('SHARE_SET',flush=True)
   c.command('@heal');c.command('@set BaseExp 0');drain(c);c.params[1]=0
   if case!='offline':peer.command('@set BaseExp 0');drain(peer);peer.params[1]=0
   print('EXP_RESET',case,flush=True)
   c.command('@monster 1008 1');b=wait(c,lambda i,b:i in (0x9fe,0x9ff) and struct.unpack_from('<H',b,23)[0]==1008);mob=struct.unpack_from('<I',b,5)[0];print('MOB',mob,flush=True)
   x=(b[63]<<2)|(b[64]>>6);y=((b[64]&63)<<4)|(b[65]>>4)
   warp(c,f'prontera {x} {y}') # Wire harness has no native client's auto-walk-to-attack.
   ident,_=entry('clif_parse_UseSkillToId');c.send(struct.pack('<HHHI',ident,1,19,mob))
   wait(c,lambda i,b:i==0x1de and struct.unpack_from('<HII',b,2)==(19,2000001,mob))
   time.sleep(2)
   ident,_=entry('clif_parse_ActionRequest');c.send(struct.pack('<HIB',ident,mob,7))
   hits=set();last_attack=time.monotonic()
   def dead(i,b):
    global last_attack
    if time.monotonic()-last_attack>3:
     ident,_=entry('clif_parse_ActionRequest');c.send(struct.pack('<HIB',ident,mob,7));last_attack=time.monotonic()

    if i==0x8c8 and struct.unpack_from('<I',b,6)[0]==mob:hits.add(struct.unpack_from('<I',b,2)[0])
    return i==0x80 and struct.unpack_from('<I',b,2)[0]==mob and b[6]==1
   try:wait(c,dead,60)
   except Exception:
    print("FAILED_ATTACK",sorted(hits),c.params,flush=True);raise
   ident,_=entry('clif_parse_StopAttack');c.send(struct.pack('<H',ident));time.sleep(.3);drain(c)
   if case!='offline':drain(peer)
   exp=(c.params.get(1,0),peer.params.get(1,0) if case!='offline' else 0);assert exp[0]>0,exp
   assert (exp[1]>0)==(bool(share) and case=='far'),(share,exp)
   for aid in aids:assert state(c,aid)['exp']==0
   if baseline is None:baseline=exp
   else:assert exp==baseline,(formula,share,n,baseline,exp,hits)
   if n:assert hits.intersection(aids),(n,hits)
   results.append(dict(eligibility=case,formula=formula,share=share,companions=n,owner_exp=exp[0],peer_exp=exp[1],attackers=sorted(hits)))
   print(results[-1],flush=True)
   c.command('@companion dismiss');text(c,'Companion dismissed')
peer.close();c.close();(R/'artifacts/m9-exp-results.json').write_text(json.dumps(results,indent=2))
