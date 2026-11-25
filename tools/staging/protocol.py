import json, pathlib, socket, struct, time
TABLE=json.loads(pathlib.Path('/tests/wire-packets.json').read_text())
def entry(fn):return next((int(k),v) for k,v in TABLE.items() if v['function']==fn)
class Client:
 def __init__(self,port):
  self.s=socket.create_connection(('127.0.0.1',port),10);self.s.settimeout(10);self.params={}
 def exact(self,n):
  out=b''
  while len(out)<n:
   b=self.s.recv(n-len(out))
   if not b:raise EOFError('server closed connection')
   out+=b
  return out
 def packet(self):
  h=self.exact(2);id=struct.unpack('<H',h)[0]
  if str(id) not in TABLE:raise RuntimeError(f'unknown packet {id:#x}')
  n=TABLE[str(id)]['length']
  if n==-1:h+=self.exact(2);n=struct.unpack_from('<H',h,2)[0]
  assert 2<=n<=65535,(id,n)
  packet=h+self.exact(n-len(h))
  if id==0xacb:self.params[struct.unpack_from('<H',packet,2)[0]]=struct.unpack_from('<Q',packet,4)[0]
  if id==0xb0:self.params[struct.unpack_from('<H',packet,2)[0]]=struct.unpack_from('<I',packet,4)[0]
  return id,packet
 def until(self,ids):
  deadline=time.monotonic()+15
  for _ in range(3000):
   assert time.monotonic()<deadline, ids
   id,b=self.packet()
   if id in ids:return id,b
  raise AssertionError('packet not found')
 def send(self,b):self.s.sendall(b)
 def command(self,cmd):
  id,e=entry('clif_parse_GlobalMessage');msg=(getattr(self,'name','StageOwner')+' : '+cmd).encode()+b'\0'
  self.send(struct.pack('<HH',id,len(msg)+4)+msg)
 def close(self):self.s.close()
def login(fixture_path='/stage/fixture.json'):
 deadline=time.monotonic()+900
 while "Map Server is now online." not in pathlib.Path("/stage/artifacts/map-server.log").read_text(errors="replace"):
  assert time.monotonic()<deadline, "map server did not become ready"
  time.sleep(.2)
 fixture=json.loads(pathlib.Path(fixture_path).read_text())
 # Native Login may still acknowledge the last session while Char finalizes logout.
 # Handle ONLY the explicit 'last login still recognized' response, bounded to 40 seconds.
 retry_end=time.monotonic()+40
 while True:
  c=Client(16900)
  c.send(struct.pack('<HI24s24sB',0x64,20211103,fixture['username'].encode(),fixture['password'].encode(),0))
  id,b=c.until({0xac4,0x69,0x6a,0x83e,0x81})
  if id==0x81 and b[2]==8 and time.monotonic()<retry_end:
   c.close();print('LOGIN waiting for native previous-session cleanup',flush=True);time.sleep(3);continue
  assert id in (0xac4,0x69),f'login refused {id:#x}'
  break
 token1,aid,token2=struct.unpack_from('<III',b,4);sex=b[46];c.close()
 c=Client(16121);c.send(struct.pack('<HIIIHB',0x65,aid,token1,token2,0,sex));assert struct.unpack('<I',c.exact(4))[0]==aid
 c.until({0x6b});c.send(struct.pack('<HB',0x66,fixture.get('slot',0)));_,b=c.until({0xac5,0x71});cid=struct.unpack_from('<I',b,2)[0];c.close()
 c=Client(15121);id,e=entry('clif_parse_WantToConnection');b=bytearray(e['length']);struct.pack_into('<H',b,0,id)
 for off,value,fmt in zip(e['offsets'],[aid,cid,token1,int(time.time()) & 0xffffffff,sex],['I','I','I','I','B']):struct.pack_into('<'+fmt,b,off,value)
 c.send(b)
 # The map server sends its AID as a framed ZC_AID packet; consume until map entry.
 c.until({0x73,0x2eb,0xa18})
 id,e=entry('clif_parse_LoadEndAck');c.send(struct.pack('<H',id));time.sleep(1)
 c.name=fixture.get('name','StageOwner')
 return c
if __name__=='__main__':
 c=login();c.command('@where StageOwner')
 deadline=time.monotonic()+15
 while time.monotonic()<deadline:
  ident,b=c.packet()
  if ident==0x8e and b'prontera' in b:
   print('LOGIN_CHAR_MAP_WHERE_PASS',b[4:].decode(errors='replace'));break
 else:raise AssertionError('where reply missing')
 c.close()
