"""Read the shadow risk estimate; publish only a timestamp and admission bit."""
import json,sys,re
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'brain_stage2'))
from planner import World,Planner,readlog

_,_,source,model=sys.argv
world=World();planner=Planner(json.loads(Path(model).read_text()),trial_radius=4)
dest=Path(source).with_name('trial.command')
offer=0
previous=None
def observed():
    global offer
    for line in readlog(Path(source),True):
        match=re.search(r'B_OFFER (\d+) (\d+) ',line)
        if match:offer=int(match[2])
        yield line

for kind,frame in world.frames(observed()):
    if kind!='frame':continue
    if offer!=previous:
        planner.strategy_due=0
        previous=offer
    frame['admission_offer']=offer
    plan=planner.think(frame,world)
    if 'safe' in plan and not dest.with_name('trial.disconnect').exists():
        tmp=dest.with_suffix('.tmp')
        permit=bool(offer and plan['safe'] and plan['ttd'][frame['pull']]>(plan['help_if_hit'][frame['pull']] or 120)+2.5)
        plan['offered']=offer;plan['permit']=permit
        tmp.write_text(f"{frame['t']} {int(permit)} {offer} 0 0\n")
        tmp.replace(dest)
    print(json.dumps(plan,separators=(',',':')),flush=True)
