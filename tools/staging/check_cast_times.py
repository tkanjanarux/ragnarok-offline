"""Read unbuffed level-five bolt cast times from the actual map-server cast packets."""
import re
import struct
import time
from nearby_hunt_fixture import c, mage, egg, stage, wait, api
from companion_ai_fixture import attack,owner
from protocol import entry

pid,actor=mage['id'],mage['actor']
api(c,f'skills {pid} none')
c.command('@set JobLevel 36')
script=stage/'npc/custom/qa_bolt_time.txt'
script.write_text('-\tscript\tQA Bolt Times\t-1,{\nOnInit: bindatcmd "timebolt",strnpcinfo(3)+"::OnCast",99,99; end;\nOnCast: unitskilluseid atoi(.@atcmd_parameters$[0]),atoi(.@atcmd_parameters$[1]),5,atoi(.@atcmd_parameters$[2]); end;\n}\n')
c.command('@loadnpc npc/custom/qa_bolt_time.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
mob=egg(150,180,1097)
attack(c,mob)
wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(owner,mob) and struct.unpack_from('<i',b,22)[0]>0)
c.send(struct.pack('<H',entry('clif_parse_StopAttack')[0]))
api(c,f'assist {pid}')
for level in range(78,82):
    c.command(f'@set BaseLevel {level}')
    time.sleep(1)  # Max HP/SP update on the companion follow tick.
    c.command(f"#heal {mage['name']}")
    c.command("@heal")
    c.command('@companion status')
    msg=wait(c,lambda i,b:i==0x8e and f'Companion id={actor} '.encode() in b)
    stats={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',msg.decode(errors='replace'))}
    assert stats['base']==level
    times=[]
    for sk in (19,14,20):
        c.command(f'@timebolt {actor} {sk} {mob}')
        p=wait(c,lambda i,b:i in (0x13e,0x7fb,0xb1a) and struct.unpack_from('<II',b,2)==(actor,mob) and struct.unpack_from('<H',b,14)[0]==sk)
        times.append(struct.unpack_from('<I',p,20)[0])
        wait(c,lambda i,b:i==0x1de and struct.unpack_from('<HII',b,2)==(sk,actor,mob))
        time.sleep(1)
    print(level,[stats[k] for k in ('dex','int','vit')],[stats['total_'+k] for k in ('dex','int','vit')],times,flush=True)
    assert len(set(times))==1 and min(times)>0
c.close()
