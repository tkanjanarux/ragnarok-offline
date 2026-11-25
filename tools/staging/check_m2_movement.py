"""Wire + GM observation tests, called by the existing lifecycle harness."""
import time,struct
from protocol import entry

def verify_movement(c,aid,text):
 def position(name=None):
  name = name or f'Companion{aid}'
  c.command(f'@where {name}')
  while True:
   ident,b=c.packet()
   if ident==0x8e and (name+' ').encode() in b:
    name,m,x,y=b[4:].rstrip(b'\0').decode().split()
    return m,int(x),int(y)
 def warp(m,x,y):
  c.command(f'@warp {m} {x} {y}');c.until({0x91})
  ident,_=entry('clif_parse_LoadEndAck');c.send(struct.pack('<H',ident))
 def close_to(m,x,y):
  # @warp can choose a nearby walkable cell; compare with actual owner placement.
  actual=position('StageOwner');assert actual[0]==m
  m,x,y=actual
  deadline=time.monotonic()+12
  while time.monotonic()<deadline:
   p=position()
   if p[0]==m and max(abs(p[1]-x),abs(p[2]-y))<=4:return p
   time.sleep(.25)
  raise AssertionError(('not following',p,m,x,y))
 c.command('@companion stop');text(c,'Companion stopped.')
 held=position();warp('prontera',160,180);time.sleep(1)
 assert position()==held,'stop did not hold position'
 c.command('@companion follow');text(c,'Companion following.')
 # A normal movement packet from the synthetic actor, not only teleport placement.
 deadline=time.monotonic()+10;walk=False
 while time.monotonic()<deadline:
  ident,b=c.packet()
  if (ident==0x86 and struct.unpack_from('<I',b,2)[0]==aid) or (ident==0x9fd and struct.unpack_from('<I',b,5)[0]==aid):
   walk=True;break
 assert walk,'standard actor walk packet absent'
 close_to('prontera',160,180)
 c.command('@companion stop');text(c,'Companion stopped.');held=position()
 warp('izlude',128,114);time.sleep(1)
 assert position()==held,'stopped actor followed map change'
 c.command('@companion follow');text(c,'Companion following.')
 close_to('izlude',128,114)
 for _ in range(3):
  warp('prontera',150,180);close_to('prontera',150,180)
  warp('izlude',128,114);close_to('izlude',128,114)
 warp('prontera',150,180);close_to('prontera',150,180)
 warp('prontera',150,210);close_to('prontera',150,210)
 warp('prontera',150,180);close_to('prontera',150,180)
 return dict(follow_walk_packet=True,stop_holds_position=True,stop_holds_across_maps=True,
             resume_cross_map=True,repeated_cross_map=True,long_distance_catchup=True)
