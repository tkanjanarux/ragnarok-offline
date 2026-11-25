"""Time two successive native bolts after a real Priest applies Suffragium."""
import struct,time
from nearby_hunt_fixture import c,mage,priest,egg,stage,api,wait
from companion_ai_fixture import attack,owner
from protocol import entry
c.command('@set BaseLevel 81')
c.command('@set JobLevel 36')
api(c,f"skills {mage['id']} none")
api(c,f"skills {priest['id']} suffragium,heal")
script=stage/'npc/custom/qa_two_casts.txt'
script.write_text('-\tscript\tQA Two Casts\t-1,{\nOnInit: bindatcmd "bolt5",strnpcinfo(3)+"::OnCast",99,99; end;\nOnCast: unitskilluseid atoi(.@atcmd_parameters$[0]),19,5,atoi(.@atcmd_parameters$[1]); end;\n}\n')
c.command('@loadnpc npc/custom/qa_two_casts.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
target=egg(150,180)
attack(c,target)
wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(owner,target) and struct.unpack_from('<i',b,22)[0]>0)
c.send(struct.pack('<H',entry('clif_parse_StopAttack')[0]))
api(c,f"assist {mage['id']}")
def bolt():
    c.command(f"@bolt5 {mage['actor']} {target}")
    p=wait(c,lambda i,b:i in (0x13e,0x7fb,0xb1a) and struct.unpack_from('<II',b,2)==(mage['actor'],target))
    delay=struct.unpack_from('<I',p,20)[0]
    wait(c,lambda i,b:i==0x1de and struct.unpack_from('<HII',b,2)==(19,mage['actor'],target))
    time.sleep(1)
    return delay
time.sleep(1)  # Wait for the native owner-level synchronization tick.
before=bolt()
c.command(f"@companion ui 954 assist {priest['id']}")
wait(c,lambda i,b:i==0x9cb and struct.unpack_from('<H',b,2)[0]==67 and struct.unpack_from('<I',b,8)[0]==mage['actor'])
after=[bolt(),bolt()]
assert after[0]==after[1] and abs(after[0]-(700+(before-700)*.8))<2,(before,after)
print('PASS native Suffragium III, unbuffed and two buffed Lv.5 Fire Bolts (ms)',before,after)
c.close()
