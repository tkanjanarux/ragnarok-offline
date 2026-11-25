"""A short-lived one-cell movement/skill lease for the isolated stage-three actuator."""
import json
import os
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'brain_stage2'))
from planner import CAMP, W, Planner, World, Influence, readlog, pos, dist, attack_distance

def decide(frame,world,plan,probe):
    a=frame['a'];pull=frame['pull'];start=pos(a[pull]);anchor=frame['anchor']
    home=pos(a[CAMP]); t=frame['t']
    if probe in ('orc','orc_late'):return (0,*start,0)
    grid=Influence(frame,world)
    # Preflight uses a single synthetic step in a cleared field, without a tag.
    if probe:
        goal=(anchor[0]+1,anchor[1])
    elif dist(start,anchor)>1 and (not plan['safe'] or frame['pack']):
        goal=anchor
    elif plan.get('prep') and plan['prep']['action']=='kyrie':
        v=plan['prep']
        if v['actor']==CAMP and list(home)==list(v['cell']):
            return (3,*home,v['target'])
        return (0,*start,0)
    elif plan['safe'] and plan.get('goal'):
        # Retain the original portfolio safety envelope in addition to the new leash.
        if plan['ttd'][pull] < (plan['help_if_hit'][pull] or 120)+2.5:return (0,*start,0)
        goal=tuple(plan['goal'])
        for mid,m in frame['m'].items():
            if tuple(m[3:5])==goal and dist(goal,start)<=1 and dist(goal,anchor)<=4 and all(frame['elig'][mid][:2]):
                return (2,*start,mid)
    else:return (0,*start,0)
    if start==goal:return (0,*start,0)
    route=grid.route(start,goal)
    if route:
        cell=route[0]
        if dist(cell,anchor)<=4 and dist(cell,home)<=6 and attack_distance({448:'yuno_fild07',450:'yuno_fild09'}[a[CAMP][3]],home,cell,9,0)==0:
            return (1,*cell,0)
    return (0,*start,0)

def main():
    _,log,model=sys.argv[1:]
    log=Path(log); output=log.with_name('trial.command')
    world=World();planner=Planner(json.loads(Path(model).read_text()),trial_radius=4)
    for kind,frame in world.frames(readlog(log,True)):
        if kind!='frame':continue
        plan=planner.think(frame,world)
        if 'safe' in plan:
            action=decide(frame,world,plan,os.environ.get('TRIAL_PROBE',''))
            tmp=output.with_suffix('.tmp');tmp.write_text(' '.join(map(str,(frame['t'],*action)))+'\n')
            if not output.with_name('trial.disconnect').exists():tmp.replace(output)
            plan['lease']=action
        print(json.dumps(plan,separators=(',',':')),flush=True)

if __name__=='__main__':main()
