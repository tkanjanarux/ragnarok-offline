"""Mage opens without a Knight, Stop cancels damage, and Priest never initiates."""
import time
from nearby_hunt_fixture import c, knight, mage, ui, api, egg, hp, see_hit, position, chat
from protocol import login
from check_m4_exp import warp

api(c,f"skills {mage['id']} firebolt")
api(c,f"bench {knight['id']}")
target=egg(155,180)
ui('hunt on',1)
see_hit(mage['actor'],target)
print('PASS Mage opens without Knight')
api(c,f"stop {mage['id']}")
ui('list',0)
stopped_hp=hp(target)
time.sleep(2)
assert hp(target)==stopped_hp
# A target can become unreachable after a successful opener.
c.command('@killmonster2')
target=egg(150,184)
ui('hunt on',1)
see_hit(mage['actor'],target)
c.command('@huntwall 1')
time.sleep(1)
blocked_hp=hp(target)
time.sleep(2)
assert hp(target)==blocked_hp
assert position(mage['name']) and max(abs(a-b) for a,b in zip(position(mage['name']),position('StageOwner')))<=4
api(c,f"stop {mage['id']}")
ui('list',0)
c.command('@huntwall 0')
print('PASS active target became unreachable; pending attacks stopped, Mage regrouped')
api(c,f"bench {mage['id']}")
chat('hunt on')
held=hp(target)
time.sleep(2)
assert hp(target)==held
print('PASS profile Stop disables hunt, lone Priest does not initiate')
warp(c,'izlude 128 114')
ui('list',0)
chat('hunt on')
c.close()
reconnected=login()
ui('list',0,reconnected)
print('PASS cross-map warp and reconnect clear hunt, chat and UI agree')
reconnected.close()
