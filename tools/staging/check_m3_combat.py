import pathlib
"""M3 real protocol party membership and melee assist smoke test."""
import time,struct,re
from protocol import entry,login

def status(c):
 c.command('@companion status')
 while True:
  ident,b=c.packet()
  if ident==0x8e and b'Companion id=' in b:
   return {k:int(v) for k,v in re.findall(r'(id|party|assist|hp|target)=(\d+)',b.decode(errors='replace'))}

def joined(c,aid):
 deadline=time.monotonic()+10
 while time.monotonic()<deadline:
  s=status(c)
  if s['party']>0:
   assert s['id']==aid
   return s
  time.sleep(.1)
 raise AssertionError('companion did not join party')

def move_to_spawn(c, packet):
 # The wire client does not implement the game's click-to-chase movement.
 from check_m4_exp import warp
 x=(packet[63]<<2)|(packet[64]>>6)
 y=((packet[64]&63)<<4)|(packet[65]>>4)
 warp(c,f'prontera {x} {y}')
 time.sleep(.6)

def verify_combat(c,aid,text):
 c.command('@party CompanionM3')
 deadline=time.monotonic()+15;roster=False
 while time.monotonic()<deadline:
  ident,b=c.packet()
  if ident==0xae5 and struct.pack('<II',aid,aid) in b and b'StageOwner' in b:
   roster=True;break
 assert roster,'normal party roster packet missing synthetic member'
 joined(c,aid)
 c.command('@companion assist');text(c,'Companion assisting your attacks.')
 assert status(c)['assist']==1
 c.command('@monster 1008 1')
 deadline=time.monotonic()+15;mob=None
 while time.monotonic()<deadline:
  ident,b=c.packet()
  if ident in (0x9fe,0x9ff) and struct.unpack_from('<H',b,23)[0]==1008:
   mob=struct.unpack_from('<I',b,5)[0];break
 assert mob,'Pupa spawn missing'
 move_to_spawn(c,b)
 ident,e=entry('clif_parse_ActionRequest');packet=bytearray(e['length']);struct.pack_into('<H',packet,0,ident)
 struct.pack_into('<I',packet,e['offsets'][0],mob);packet[e['offsets'][1]]=7
 c.send(packet)
 deadline=time.monotonic()+25;hits=[]
 while time.monotonic()<deadline:
  ident,b=c.packet()
  if ident==0x8c8 and struct.unpack_from('<II',b,2)==(aid,mob):
   damage=struct.unpack_from('<i',b,22)[0]
   if damage>0:hits.append(damage)
   if len(hits)>=1:break
 assert len(hits)>=1,('companion melee damage absent',hits)
 # Let the native attack timers finish the monster; verify a real death packet.
 deadline=time.monotonic()+25;dead=False
 while time.monotonic()<deadline:
  ident,b=c.packet()
  if ident==0x80 and struct.unpack_from('<I',b,2)[0]==mob and b[6]==1:
   dead=True;break
 assert dead,'companion did not finish the monster'
 c.command('@companion stop');text(c,'Companion stopped.')
 assert status(c)['assist']==0 and status(c)['target']==0
 # Stop the test owner's attack with a normal stop-attack packet.
 ident,e=entry('clif_parse_StopAttack');c.send(struct.pack('<H',ident))
 c.command('@killmonster2')
 c.command('@companion follow');text(c,'Companion following.')
 return dict(normal_party_roster_packet=True,local_party_join=True,assist_melee_damage=hits,
             stop_clears_combat_target=True,monster_killed=True)


def verify_multiplayer(c,aid):
 peer=login('/stage/peer-fixture.json')
 c.send(struct.pack('<HI',0xfc,2000002))
 _,invite=peer.until({0x2c6})
 party=struct.unpack_from('<I',invite,2)[0]
 peer.send(struct.pack('<HIB',0x2c7,party,1))
 deadline=time.monotonic()+15
 while time.monotonic()<deadline:
  ident,b=c.packet()
  if ident==0xae5 and b'StagePeer' in b and struct.pack('<II',aid,aid) in b:break
 else:raise AssertionError('roster refresh lost real member or companion')
 assert status(c)['party']==party
 # Leadership must stay with a real player, never the synthetic actor.
 c.send(struct.pack('<HI',0x7da,aid));time.sleep(.5)
 assert status(c)['party']==party
 peer.close()
 return dict(real_player_party_join=True,synthetic_roster_survives_char_refresh=True,
             synthetic_leadership_rejected=True)

def verify_edges(c,spawn,dismiss,detached,text):
 aid=spawn(c);joined(c,aid)
 c.command('@companion assist');text(c,'Companion assisting your attacks.')
 c.command('@monster 1008 1');mob=None
 while not mob:
  ident,b=c.packet()
  if ident in (0x9fe,0x9ff) and struct.unpack_from('<H',b,23)[0]==1008:
   mob=struct.unpack_from('<I',b,5)[0]
 move_to_spawn(c,b)
 ident,_=entry('clif_parse_ActionRequest');c.send(struct.pack('<HIB',ident,mob,7))
 deadline=time.monotonic()+20
 while time.monotonic()<deadline:
  ident,b=c.packet()
  if ident==0x8c8 and struct.unpack_from('<II',b,2)==(aid,mob):break
 else:raise AssertionError('no in-flight attack to dismiss')
 dismiss(c,aid);detached(aid)
 time.sleep(1)
 ident,_=entry('clif_parse_StopAttack');c.send(struct.pack('<H',ident));c.command('@killmonster2')
 aid=spawn(c);joined(c,aid)
 c.send(struct.pack('<HI24s',0x103,aid,f'Companion{aid}'.encode()))
 detached(aid)
 aid=spawn(c);joined(c,aid)
 c.send(struct.pack('<H',0x100))
 deadline=time.monotonic()+10
 while status(c)['party']:
  assert time.monotonic()<deadline,'old party reference after owner leave'
  time.sleep(.1)
 c.command('@party CompanionM3Next');joined(c,aid)
 # Death via the normal GM character-command path; no test-only engine hooks.
 c.command(f'#kill Companion{aid}')
 if pathlib.Path('/stage/M5_TEST').exists():
  time.sleep(1)
  assert status(c)['hp']==0
  dismiss(c,aid)
 detached(aid)
 aid=spawn(c);joined(c,aid)
 c.command('@setbattleflag companion_enable 0');text(c,'as requested');detached(aid)
 c.command('@setbattleflag companion_enable 1');text(c,'as requested')
 return dict(combat_dismiss_cleanup=True,party_kick_cleanup=True,owner_party_leave_detaches=True,new_party_rebind=True,
             companion_death_cleanup=True,disable_live_actor_cleanup=True)
