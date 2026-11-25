"""Use a timed native Heal cast to observe targeting, interruption, and emergency use."""
import struct
import time
from companion_ai_fixture import api, owner, stage, wait
from potion_ai_fixture import PotionFixture

f=PotionFixture(7)
c=f.c
c.command('@jobchange 8')
c.command('@allskill')
c.command('@heal')
api(c,f'skills {f.pid} none')
f.command('assist')
time.sleep(.6)
r=f.refresh()
f.seed({504:6})
expected=f.stock()
path=stage/'npc/custom/test_pending_heal.txt'
path.write_text('-\tscript\tPendingHealTest\t-1,{\nOnInit:\n'
                'bindatcmd "potionhealtest",strnpcinfo(3)+"::OnCast",99,99; end;\n'
                'OnCast:\nunitskilluseid getcharid(3),28,10,atoi(.@atcmd_parameters$[0]),6; end;\n}\n')
c.command('@loadnpc npc/custom/test_pending_heal.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)

def cast(target):
    c.command(f'@potionhealtest {target}')
    wait(c,lambda i,b:i in (0x13e,0x7fb,0xb1a) and struct.unpack_from('<II',b,2)==(owner,target)
         and struct.unpack_from('<H',b,14)[0]==28)

def used():
    assert f.next_use(expected,3)==504
    expected[504]-=1
    assert f.stock()==expected

cast(r['actor'])
f.set('Hp',r['max_hp']*40//100)
time.sleep(2.6)
assert f.stock()==expected,'drank during targeted Heal'
# Dropping to emergency HP while that same Heal is pending overrides the wait.
f.set('Hp',1)
used()
f.set('Hp',r['max_hp'])
wait(c,lambda i,b:i==0x9cb and struct.unpack_from('<H',b,2)[0]==28)
print('PASS targeted Heal suppressed HP potion; critical HP used exactly one')
time.sleep(1)
cast(owner)
f.set('Hp',r['max_hp']*40//100)
used()
f.set('Hp',r['max_hp'])
wait(c,lambda i,b:i==0x9cb and struct.unpack_from('<H',b,2)[0]==28)
time.sleep(1)
cast(r['actor'])
f.set('Hp',r['max_hp']*40//100)
time.sleep(2.5)
assert f.stock()==expected
c.command('@die')  # Interrupt the healer, not the patient.
used()
print('PASS another target and interrupted cast do not block use; stock',expected)
c.close()
