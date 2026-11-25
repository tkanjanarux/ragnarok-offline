"""Target eligibility and explicit owner override with a separate real player."""
import struct
import time
from nearby_hunt_fixture import c, knight, mage, ui, egg, hp, see_hit, owner, api
from protocol import login, entry
from check_m4_exp import warp

api(c,f"skills {knight['id']} none")
api(c,f"skills {mage['id']} firebolt")
# Test passive targets plus one previously hit by a separate real player.
peer=login('/stage/peer-fixture.json')
warp(peer,'prontera 150 180')
foreign=egg(151,180,1078)
action,_=entry('clif_parse_ActionRequest')
# An attack animation can also represent a miss. Establish a real damage
# claim before expecting the party to exclude this monster.
for _ in range(8):
    peer.send(struct.pack('<HIB',action,foreign,0))
    see_hit(2000002,foreign)
    time.sleep(1.2)
    foreign_hp=hp(foreign)
    if foreign_hp<60000:break
assert foreign_hp<60000, 'fixture player never landed a hit'
boss=egg(150,181,1039)
blocked=egg(150,184)
c.command('@huntwall 1')
outside=egg(150,170)
boss_hp=hp(boss)
ui('hunt on',1)
time.sleep(2)
assert hp(blocked)==hp(outside)==60000 and hp(boss)==boss_hp and hp(foreign)==foreign_hp
edge=egg(150,171)
see_hit(knight['actor'],edge)
# Owner lands a single hit on a different target in melee range.
override=egg(151,180)
c.send(struct.pack('<HIB',action,override,0))
see_hit(owner,override)
see_hit(knight['actor'],override)
see_hit(mage['actor'],override)
assert hp(foreign)==foreign_hp and hp(boss)==boss_hp and hp(blocked)==60000
print('PASS nine/ten-cell boundary, unreachable egg, foreign player damage, boss exclusion, owner landed-hit override')
peer.close()
c.close()
