"""A player opens a real Warp Portal and the client receives its skill unit."""
import struct
from companion_ai_fixture import setup, wait, warp
from protocol import entry
c,_=setup()
warp(c,'prontera 150 180')
c.command('@jobchange 8')
c.command('@allskill')
c.command('@item 717 5')
c.command('@heal')
code,desc=entry('clif_parse_UseSkillToPos')
p=bytearray(desc['length'])
struct.pack_into('<H',p,0,code)
for off,value in zip(desc['offsets'],[1,27,152,180]):
    struct.pack_into('<H',p,off,value)
c.send(p)
p=wait(c,lambda i,b:i==0xabe)
dest=next(p[j:j+16] for j in range(6,len(p),16) if p[j])
c.send(struct.pack('<HH16s',0x11b,27,dest))
p=wait(c,lambda i,b:i==0x9ca and struct.unpack_from('<i',b,16)[0] in (128,129))
assert b'\x00' != p[21:22] and struct.unpack_from('<hh',p,12)==(152,180)
uid=struct.unpack_from('<I',p,4)[0]
wait(c,lambda i,b:i==0x120 and struct.unpack_from('<I',b,2)[0]==uid,45)
print('PASS real player Warp Portal visible at (152,180) then disappeared',uid,flush=True)
c.close()
