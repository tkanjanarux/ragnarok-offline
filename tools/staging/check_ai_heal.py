import struct
import time
from companion_ai_fixture import setup, api, wait, owner

c, rows = setup(8,9)
priest, mage = rows[8],rows[9]
pid = priest['id']
api(c,f'skills {pid} heal')
owner_max = c.params[6]
for preset, owner_hp, mage_hp, expected in (
    ('protect',65,30,mage['actor']), ('protect',64,60,owner),
    ('protect',90,95,None), ('conserve',65,95,None), ('protect',65,95,owner),
    ('conserve',95,35,mage['actor']),
):
    api(c,f'stop {pid}')
    api(c,f'preset {pid} {preset}')
    c.command(f"@set Hp {owner_max*owner_hp//100}")
    c.command(f"#set {mage['name']} Hp {mage['max_hp']*mage_hp//100}")
    time.sleep(.3)
    c.command(f'@companion ui 900 assist {pid}')
    def event(i,b):
        return i==0x9cb and struct.unpack_from('<H',b,2)[0]==28 and struct.unpack_from('<I',b,12)[0]==priest['actor']
    c.s.settimeout(.2)
    if expected is None:
        try: wait(c,event,2)
        except AssertionError: pass
        else: raise AssertionError('unexpected Heal')
    else:
        b=wait(c,event,5)
        assert struct.unpack_from('<I',b,8)[0]==expected,(preset,owner_hp,mage_hp,b.hex())
    c.s.settimeout(10)
    print('PASS',preset,owner_hp,mage_hp,expected)
c.close()
