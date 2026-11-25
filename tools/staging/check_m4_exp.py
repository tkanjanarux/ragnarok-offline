"""Verify real EXP deltas and native map/dead/offline eligibility, not just animations."""
import time,struct,socket
from protocol import login,entry
from check_m4_skills import summon,state,wait,dismiss_all

def drain(c):
 c.s.settimeout(.1)
 try:
  while True:c.packet()
 except socket.timeout:pass
 finally:c.s.settimeout(10)

def warp(c,where):
 c.command('@warp '+where);c.until({0x91})
 ident,_=entry('clif_parse_LoadEndAck');c.send(struct.pack('<H',ident));time.sleep(.3)

def verify_exp(c,text):
 # Each kill starts at the same real player level/EXP, and a new same-level shell.
 c.command('@set BaseLevel 10');c.command('@set BaseExp 0');c.command('@heal')
 peer=login('/stage/peer-fixture.json')
 # Peer may already be a member after the earlier M3 test: invite only if needed.
 c.send(struct.pack('<HI',0xfc,2000002));time.sleep(.5)
 peer.s.settimeout(.2)
 end=time.monotonic()+1
 while time.monotonic()<end:
  try:i,b=peer.packet()
  except socket.timeout:continue
  if i==0x2c6:peer.send(struct.pack('<HIB',0x2c7,struct.unpack_from('<I',b,2)[0],1))
 peer.s.settimeout(10)
 time.sleep(.5)
 result={}
 for case in ['same_map_far','dead','other_map','offline']:
  if case=='same_map_far':warp(peer,'prontera 50 50')
  elif case=='dead':peer.command('@die')
  elif case=='other_map':peer.command('@alive');warp(peer,'izlude 120 110')
  else:peer.close();time.sleep(1)
  c.command('@set BaseExp 0')
  if case!='offline':peer.command('@set BaseExp 0');drain(peer)
  aid=summon(c,'knight');time.sleep(.5)
  c.command('@companion skills off');text(c,'Companion skills disabled.')
  c.send(struct.pack('<HI',0x102,1));time.sleep(.5)
  assert state(c,aid)['share']==1
  c.command('@companion assist');text(c,'Companion assisting')
  drain(c);c.params[1]=0
  c.command('@monster 1008 1')
  b=wait(c,lambda i,b:i in (0x9fe,0x9ff) and struct.unpack_from('<H',b,23)[0]==1008)
  mob=struct.unpack_from('<I',b,5)[0]
  from check_m3_combat import move_to_spawn
  move_to_spawn(c,b)
  ident,_=entry('clif_parse_ActionRequest');c.send(struct.pack('<HIB',ident,mob,7))
  wait(c,lambda i,b:i==0x80 and struct.unpack_from('<I',b,2)[0]==mob and b[6]==1)
  ident,_=entry('clif_parse_StopAttack');c.send(struct.pack('<H',ident))
  time.sleep(.3);fake=state(c,aid)['exp'];drain(c)
  own=c.params[1]
  assert own==fake and own>0,(case,own,fake)
  peerexp=None
  if case!='offline':
   drain(peer);peerexp=peer.params.get(1,0)
   assert peerexp==(own if case=='same_map_far' else 0),(case,own,peerexp)
  result[case]={'owner_exp':own,'companion_exp':fake,'peer_exp':peerexp}
  dismiss_all(c,[aid],text)
 return {'native_exp_share_cases':result}
