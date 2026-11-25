"""Real companion combat, server-reported roster state and movement on a disposable map."""
import re
import struct
import time

from companion_ai_fixture import setup, api, wait, stage, spawn, owner
from check_m4_exp import warp
from protocol import login

c, party = setup(7, 8, 9)
knight, priest, mage = [party[j] for j in (7,8,9)]
fixture = stage/'npc/custom/qa_nearby_hunt.txt'
fixture.write_text("""-	script	QA Nearby Hunt	-1,{
OnInit:
 bindatcmd "huntplace",strnpcinfo(3)+"::OnPlace",99,99;
 bindatcmd "huntremove",strnpcinfo(3)+"::OnRemove",99,99;
 bindatcmd "huntwall",strnpcinfo(3)+"::OnWall",99,99;
 bindatcmd "hunthp",strnpcinfo(3)+"::OnHP",99,99;
 end;
OnPlace:
 .@spec=atoi(.@atcmd_parameters$[0]); .@x=atoi(.@atcmd_parameters$[1]); .@y=atoi(.@atcmd_parameters$[2]);
 monster "prontera",.@x,.@y,"Hunt QA",.@spec,1;
 .@m=$@mobid[0];
 setunitdata .@m,UMOB_MODE,(.@spec==1039 ? MD_NOCAST|MD_MVP : MD_NOCAST|MD_KNOCKBACKIMMUNE);
 setunitdata .@m,UMOB_MAXHP,60000; setunitdata .@m,UMOB_HP,60000;
 unitwarp .@m,"prontera",.@x,.@y;
 getunitdata .@m,.@data;
 debugmes "HUNT_SPAWN "+.@m+" at "+.@data[UMOB_X]+" "+.@data[UMOB_Y]; end;
OnRemove:
 unitkill atoi(.@atcmd_parameters$[0]); end;
OnWall:
 .@on=atoi(.@atcmd_parameters$[0]);
 for (.@x=149;.@x<=151;.@x++)
   for (.@y=183;.@y<=185;.@y++)
     if (.@x!=150 || .@y!=184) setcell "prontera",.@x,.@y,.@x,.@y,cell_walkable,!.@on;
 end;
OnHP:
 .@m=atoi(.@atcmd_parameters$[0]); getunitdata .@m,.@data;
 debugmes "HUNT_HP "+.@m+" "+.@data[UMOB_HP]; end;
}
""")
c.command('@loadnpc npc/custom/qa_nearby_hunt.txt')
wait(c,lambda i,b: i==0x8e and b'Script loaded' in b)

def egg(x,y,species=1097):
    return query(f'@huntplace {species} {x} {y}', r'HUNT_SPAWN (\d+)')

def query(command, pattern):
    log = stage/'artifacts/map-server.log'
    offset = log.stat().st_size
    c.command(command)
    for _ in range(100):
        with log.open('rb') as f:
            f.seek(offset)
            hit = re.search(pattern.encode(), f.read())
        if hit:
            return int(hit[1])
        time.sleep(.05)
    raise AssertionError(command)

def hp(mob):
    return query(f'@hunthp {mob}',fr'HUNT_HP {mob} (\d+)')

seq = 100
def ui(action, expected, client=None):
    client = client or c
    global seq
    seq += 1
    client.command(f'@companion ui {seq} {action} ui2 hunt1')
    tag = f'[RCO1] {seq} '.encode()
    wait(client,lambda i,b: i==0x8e and tag+b'hunt '+str(expected).encode() in b)
    wait(client,lambda i,b: i==0x8e and tag+b'end ' in b)

def chat(action):
    c.command('@companion '+action)
    wait(c,lambda i,b: i==0x8e and b'Nearby hunt ' in b)

def position(name):
    c.command('@where '+name)
    b=wait(c,lambda i,b:i==0x8e and (name+' prontera ').encode() in b)
    return tuple(map(int,b[4:].rstrip(b'\0').split()[-2:]))

def damage(i,b):
    if i==0x1de:
        return struct.unpack_from('<HII',b,2)
    if i==0x8c8:
        return (0,*struct.unpack_from('<II',b,2))
    return (None,None,None)

def see_hit(actor,mob):
    wait(c,lambda i,b: damage(i,b)[1:]==(actor,mob),18)
