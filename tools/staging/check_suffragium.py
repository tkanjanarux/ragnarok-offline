"""New/legacy wire tables, ranks, native party status and Heal priority."""
import struct,time
from companion_ai_fixture import setup,api,stage,wait,owner
c,rows=setup(8,9)
priest,mage=rows[8],rows[9]
pid=priest['id']
seq=9000
def skills(cap):
    global seq
    seq+=1
    c.command(f'@companion ui {seq} inspect {pid} ui2 skills{cap} gear2 syrup1 hunter1 hunt1')
    ranks={}
    while True:
        _,b=c.until({0x8e})
        t=b[4:].rstrip(b'\0').split()
        if t[:2]!=[b'[RCO1]',str(seq).encode()]:continue
        if t[2]==b'skill':ranks[int(t[3])]=int(t[4])
        if t[2]==b'end':return ranks
for job,rank in ((19,0),(20,1),(25,2),(30,3),(36,3),(50,3)):
    c.command(f'@set JobLevel {job}')
    time.sleep(.5)
    book=skills(7)
    assert book[67]==rank and (not rank or book[66]>=2),(job,book)
assert 67 not in skills(6)
assert 'skills=' in api(c,f'skills {pid} suffragium,heal')[1]
c.command('@set Hp 1')
time.sleep(.3)
c.command(f'@companion ui 991 assist {pid}')
def support():
    p=wait(c,lambda i,b:i==0x9cb and struct.unpack_from('<H',b,2)[0] in (28,67))
    return struct.unpack_from('<H',p,2)[0],struct.unpack_from('<I',p,8)[0]
assert support()==(28,owner)
until=time.monotonic()+15
while support()!=(67,mage['actor']):assert time.monotonic()<until
# End the status after the native 30-second cooldown to simulate dispel.
p=stage/'npc/custom/test_suffragium.txt'
p.write_text('-\tscript\tQA Suffragium\t-1,{\nOnInit: bindatcmd "clearcastbuff",strnpcinfo(3)+"::OnClear",99,99; end;\nOnClear: sc_end SC_SUFFRAGIUM,atoi(.@atcmd_parameters$[0]); end;\n}\n')
c.command('@loadnpc npc/custom/test_suffragium.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
assert 'skills=heal' in api(c,f'skills {pid} heal')[1]
c.command(f"@clearcastbuff {mage['actor']}")
log=stage/'artifacts/map-server.log'
offset=log.stat().st_size
time.sleep(32.5)
assert 'skill=67 ' not in log.read_bytes()[offset:].decode(errors='replace')
api(c,f'skills {pid} suffragium,heal')
until=time.monotonic()+8
while support()!=(67,mage['actor']):assert time.monotonic()<until
print('PASS Job 20/25/30, Impositio prerequisite, compatible detail tables, Heal first, group buff reaches Wizard, disabled and refreshed on re-enable')
c.close()
