"""Reuse the original High Orc event. Limit exposure to 2 seconds and remove only this spawn."""
from pathlib import Path
source=Path('/tests/brain_stage3/fixture.py').read_text()
old='"Camp attacker",1213,12;'
new='"Camp attacker",1213,12,"QA Limited Probe::OnKilled"; sleep 2000; killmonster .@m$,"QA Limited Probe::OnKilled"; debugmes "B_CLEAR orcs";'
assert source.count(old)==1
source=source.replace(old,new)
exec(compile(source,'/tests/brain_stage3/fixture.py','exec'))
