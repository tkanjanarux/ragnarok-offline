"""A stalled team rechecks readiness without releasing a new pack unsafely."""
import re
import time

from build_fixture import BuildFixture
from nearby_hunt_fixture import c, knight, mage, priest, stage

assert (stage / 'STAGING_ONLY').is_file()
f = BuildFixture(c)
c.command('@set BaseLevel 88')
c.command('@set JobLevel 47')
f.note(f'bench {mage["id"]}')
f.select(mage['id'],'storm')
f.note(f'summon {mage["id"]}')
for row in (knight,priest,mage):
    f.note(f'assist {row["id"]}')
f.note(f'skills {mage["id"]} none')
trace = stage/'artifacts/map-server.log'
start = trace.stat().st_size
f.note('mob on')
def events():
    with trace.open('rb') as log:
        log.seek(start)
        return log.read().decode(errors='replace')
limit = time.monotonic()+100
pattern = r'from=พัก/ถอย to=เตรียม elapsed_ms=(\d+) reason=phase timeout'
next_poll=time.monotonic()+5
while time.monotonic()<limit:
    if time.monotonic()>=next_poll:
        f.frames("list")
        next_poll=time.monotonic()+5
    match=re.search(pattern,events())
    if match:break
    time.sleep(.5)
assert match and 90000 <= int(match[1]) <= 92000, events()[-3000:]
time.sleep(3)
assert events().count('to=พัก/ถอย')>=2
assert 'to=ออกลาก' not in events()
f.note(f'skills {mage["id"]} storm')
time.sleep(1)
assert 'from=พัก/ถอย to=เตรียม' in events().split('reason=phase timeout')[-1]
f.note('mob off')
c.close()
print('PASS recovery timeout at',match[1],'ms, rechecked shortage and resumed preparation after skill restore')
