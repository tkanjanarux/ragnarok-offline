"""A new monster Fire Wall must reroute a companion already walking."""
import re
import struct
import time
from companion_ai_fixture import setup, stage, api, wait, warp
from protocol import entry

c,roster=setup()
warp(c,'dew_dun02 218 259')
c.command('@killmonster2')
pid=roster[7]['id']
rows,_,_=api(c,f'summon {pid}')
actor=next(row['actor'] for row in rows if row['id']==pid)
api(c,f'follow {pid}')
(stage/'npc/custom/qa_firewalk.txt').write_text('''-	script	QA Firewalk	-1,{
OnInit:
 bindatcmd "qafirewalk",strnpcinfo(3)+"::OnRun",99,99; end;
OnRun:
 .@actor=atoi(.@atcmd_parameters$[0]);
 for (.@i=0; .@i<80; .@i++) {
  getmapxy .@map$,.@x,.@y,BL_PC,.@actor;
  debugmes "QA_WALL_STEP "+.@x+" "+.@y;
  if (!.@cast && .@x>=221) {
   monster "dew_dun02",220,259,"QA Fire Wall caster",1002,1;
   .@mob=$@mobid[0]; setunitdata .@mob,UMOB_MODE,MD_CANATTACK;
   unitskillusepos .@mob,18,10,224,259,-50,0,0,1;
   .@cast=1;
  }
  sleep2 60;
 }
 end;
}
''')
c.command('@loadnpc npc/custom/qa_firewalk.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
api(c,f'stop {pid}')
code,desc=entry('clif_parse_WalkToXY')
p=bytearray(desc['length'])
struct.pack_into('<H',p,0,code)
at=desc['offsets'][0]
x,y=230,259
p[at:at+3]=bytes((x>>2,((x&3)<<6)|(y>>4),(y&15)<<4))
c.send(p)
time.sleep(2.5)
log=stage/'artifacts/map-server.log'
offset=log.stat().st_size
cells=set()
read_packet=c.packet
def record():
    i,b=read_packet()
    if i==0x9ca and struct.unpack_from('<i',b,16)[0]==127:
        cells.add(struct.unpack_from('<hh',b,12))
    return i,b
c.packet=record
c.command(f'@qafirewalk {actor}')
api(c,f'follow {pid}')
time.sleep(5.5)
api(c,f'stop {pid}')
steps=[(int(a),int(b)) for a,b in re.findall(rb'QA_WALL_STEP (\d+) (\d+)',log.read_bytes()[offset:])]
assert (224,259) in cells and steps and steps[0][0]<=220 and steps[-1][0]>=226, (cells,steps)
assert cells.isdisjoint(steps), (cells,steps)
print('PASS companion rerouted around newly cast monster Fire Wall',sorted(cells),list(dict.fromkeys(steps)),flush=True)
c.close()
