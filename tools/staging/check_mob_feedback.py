"""Read the owner's actual chat packets while the pull decision changes."""
import time
from nearby_hunt_fixture import c, knight, priest, mage, egg, wait, stage
from build_fixture import BuildFixture

f = BuildFixture(c)
c.command('@set BaseLevel 85')
c.command('@set JobLevel 45')
for member in (knight, priest, mage):
    f.note(f'assist {member["id"]}')

def notice(fragment):
    packet = wait(c, lambda op, buf: op == 0x8e and buf[4:].startswith(b'[Mob] ')
                  and fragment.encode() in buf[4:], 12)
    print(packet[4:].rstrip(b'\0').decode(), flush=True)

c.command('@companion mob on')
notice('prontera (')
notice('Storm Gust Lv.0')
notice('เลือก build storm')
f.note('mob off')
f.note(f'bench {mage["id"]}')
f.select(mage['id'], 'storm')
f.note(f'summon {mage["id"]}')
f.note(f'assist {mage["id"]}')
c.command('@killmonster2')
assert f.note('mob 3') == 'Mob cap saved.'
c.command('@companion mob on')
notice('เป้าสูงสุด 3 ตัว')
notice('Storm Gust Lv.10 พร้อม')
notice('ไม่มีมอนในรัศมี')
mob = egg(155, 181, 2155)
notice('Butoijo')
time.sleep(5.2)  # Let the owner notification cooldown expire before the transition.
script=stage/'npc/custom/qa_mob_ready.txt'
script.write_text('-\tscript\tQA Mob Ready\t-1,{\nOnInit: monster "prontera",156,181,"Bigfoot",1060,1; end;\n}')
c.command('@loadnpc npc/custom/qa_mob_ready.txt')
notice('Knight พร้อมออกลาก')
c.command(f'@huntremove {mob}')
print('PASS chat anchor/cap, bolt, learned Storm, empty area, unsafe Butoijo and ready Knight')
c.close()
