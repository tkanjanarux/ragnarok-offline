"""Walk across each edge with one stationary target and observe authoritative HP."""
import struct
import time

from nearby_hunt_fixture import api, c, egg, hp, knight, mage, position, priest, ui
from protocol import entry


def walk_owner(y):
    packet_id, desc = entry('clif_parse_WalkToXY')
    packet = bytearray(desc['length'])
    struct.pack_into('<H', packet, 0, packet_id)
    offset = desc['offsets'][0]
    x = 150
    packet[offset:offset + 3] = bytes((x >> 2, ((x & 3) << 6) | (y >> 4), (y & 15) << 4))
    c.send(packet)
    for _ in range(40):
        if position('StageOwner') == (x, y):
            return
        time.sleep(.1)
    raise AssertionError(('owner did not arrive', y))


def check_damage(target):
    before = hp(target)
    for _ in range(60):
        time.sleep(.15)
        if hp(target) < before:
            return
    raise AssertionError(('no damage at', position('StageOwner'), before))


for member in (priest, mage):
    api(c, f"bench {member['id']}")
api(c, f"skills {knight['id']} none")
target = egg(150, 171)
walk_owner(181)
ui('hunt on', 1)
time.sleep(2)
assert hp(target) == 60000, 'initiated at ten cells'
for y in (180, 181, 183):
    walk_owner(y)
    check_damage(target)
    print('PASS active damage at distance', y - 171)
walk_owner(184)
before = hp(target)
for _ in range(60):
    x, y = position(knight['name'])
    if max(abs(150-x), abs(184-y)) <= 4:
        break
    time.sleep(.15)
else:
    raise AssertionError(('did not regroup', x, y))
time.sleep(1.5)
assert hp(target) == before, 'damage after crossing thirteen cells'
walk_owner(183)
time.sleep(2)
assert hp(target) == before, 'reacquired at twelve cells'
walk_owner(180)
check_damage(target)
ui('list', 1)
print('PASS regroup at 13, no reacquisition at 12, reacquisition at 9')
c.close()
