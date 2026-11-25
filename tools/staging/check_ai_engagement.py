import re
import struct
import time
from companion_ai_fixture import setup, api, wait, stage, spawn, attack, owner
from check_m4_exp import warp

c, rows = setup(7)
knight=rows[7]
pid, actor=knight['id'],knight['actor']
api(c,f'skills {pid} bowlingbash')
api(c,f'assist {pid}')
path=stage/'npc/custom/ai_hp_fixture.txt'
path.write_text('-\tscript\tAI HP Fixture\t-1,{\nOnInit:\n'
                'bindatcmd "aihp",strnpcinfo(3)+"::OnHP",99,99; end;\n'
                'OnHP:\n.@id=atoi(.@atcmd_parameters$[0]); if (.@atcmd_numparameters==3) '
                'unitwarp .@id,"prontera",atoi(.@atcmd_parameters$[1]),atoi(.@atcmd_parameters$[2]);\n'
                'getunitdata .@id,.@d; debugmes "QA_HP "+.@id+" "+.@d[UMOB_HP]+" "+.@d[UMOB_X]+" "+.@d[UMOB_Y]; end;\n}\n')
c.command('@loadnpc npc/custom/ai_hp_fixture.txt')
wait(c,lambda i,b: i==0x8e and b'Script loaded' in b)
log=stage/'artifacts/map-server.log'
def inspect(mob, location=''):
    offset=log.stat().st_size
    c.command(f'@aihp {mob} {location}'.strip())
    end=time.monotonic()+4
    while time.monotonic()<end:
        with log.open('rb') as f:
            f.seek(offset)
            match=re.search(rb'QA_HP '+str(mob).encode()+rb' (\d+) (\d+) (\d+)',f.read())
        if match: return tuple(map(int,match.groups()))
        time.sleep(.05)
    raise AssertionError('target HP missing')

egg,x,y=spawn(c,1097)
spectator,_,_=spawn(c,1078)
before,sx,sy=inspect(spectator,f'{x} {y}')
assert max(abs(sx-x),abs(sy-y))<=1
warp(c,f'prontera {x+5} {y}')
attack(c,egg)
wait(c,lambda i,b:i==0x139 and struct.unpack_from('<I',b,2)[0]==egg)
def hit(i,b):
    if i==0x8c8: return struct.unpack_from('<II',b,2)==(actor,egg)
    return i==0x1de and struct.unpack_from('<HII',b,2)==(62,actor,egg)
hp=inspect(egg)[0]
c.s.settimeout(.2)
try: wait(c,hit,2)
except AssertionError: pass
else: raise AssertionError('Knight pulled unengaged monster')
assert inspect(egg)[0]==hp
warp(c,f'prontera {x} {y}')
attack(c,egg)
wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(owner,egg))
wait(c,lambda i,b:i==0x1de and struct.unpack_from('<HII',b,2)==(62,actor,egg))
time.sleep(.8)
assert inspect(spectator)[0]==before,'Bowling Bash pulled an idle neighbor'
print('PASS approach held, Bowling Bash after contact, adjacent idle mob unharmed')
c.close()
