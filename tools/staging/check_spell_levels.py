"""Observe actual native cast levels against different remaining HP values."""
import re
import struct
import time
from companion_ai_fixture import setup, api, stage, spawn, attack, owner, wait
from check_m4_exp import warp

c, rows = setup(9)
wizard = rows[9]
pid = wizard['id']
api(c, f'skills {pid} firebolt')
api(c, f'preset {pid} custom')
path = stage / 'npc/custom/qa_spell_hp.txt'
path.write_text('-\tscript\tQA Spell HP\t-1,{\nOnInit: bindatcmd "qaspellhp",strnpcinfo(3)+"::OnHP",99,99; end;\n'
                'OnHP: .@m=atoi(.@atcmd_parameters$[0]); setunitdata .@m,UMOB_MODE,MD_IGNOREMELEE|MD_IGNORERANGED; '
                'setunitdata .@m,UMOB_MAXHP,60000; setunitdata .@m,UMOB_HP,atoi(.@atcmd_parameters$[1]); end;\n}\n')
c.command('@loadnpc npc/custom/qa_spell_hp.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
log = stage / 'artifacts/map-server.log'
for hp,expected in [(20,1),(400,None),(50000,8)]:
    c.command('@killmonster2')
    api(c,f'stop {pid}')
    c.command(f"#heal {wizard['name']}")
    warp(c,'prontera 150 180')
    mob,x,y = spawn(c,1097)
    c.command(f'@qaspellhp {mob} {hp}')
    warp(c,f'prontera {x} {y}')
    start = log.stat().st_size
    api(c,f'assist {pid}')
    attack(c,mob)
    wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(owner,mob))
    deadline=time.monotonic()+10
    while time.monotonic()<deadline:
        with log.open('rb') as f:
            f.seek(start)
            cast=re.search(fr"cast id={wizard['actor']} skill=19 target={mob} sp=\d+ level=(\d+)".encode(),f.read())
        if cast:break
        time.sleep(.2)
    assert cast,(hp,expected)
    level = int(cast[1])
    assert (1 < level < 8 if expected is None else level == expected),(hp,expected,level)
    print('PASS remaining HP',hp,'native cast level',level)
c.close()
