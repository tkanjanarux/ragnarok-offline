"""Independent one-action, full-policy roll-forward from saved shadow proposals."""
import json
import sys
from collections import Counter
from copy import deepcopy
from pathlib import Path
from planner import Planner,World,readlog,attack_distance,reachable_wave,attack_delays,pos,dist,TEAM,P,K

def evaluate(d,model):
    rows={r['t']:r for l in (d/'decisions.jsonl').read_text().splitlines() if 'safe' in (r:=json.loads(l))}
    # Last decision has no measured interval and is excluded by prep_audit.
    if rows:rows.pop(max(rows))
    w=World();first=None;outside=returned=False;prior=None;until=0;counts=Counter()
    for kind,f in w.frames(readlog(next(d.glob('*.gz')),False)):
        if kind!='frame':continue
        t=f['t'];first=t if first is None else first
        pull=f['a'][f['pull']]
        gap=dist(pos(pull),f['anchor']);outside|=gap>9;returned|=outside and gap<=5
        if t not in rows:continue
        plan=rows[t].get('prep')
        if not plan:
            prior=None
            continue
        key=(plan['actor'],plan['target'],plan['action'],tuple(plan['cell']))
        if prior==key or t<until:continue
        until=t+round(plan['seconds']*1000);prior=key
        s=deepcopy(f);s['t']=until
        a=s['a'][plan['actor']];a[4:6]=plan['cell'];a[10:13]=[*plan['cell'],0]
        a[8]-=plan['sp']
        if plan['action']=='kyrie':
            s['buff'][plan['target'],39]=[*plan['remaining_shield'],until+118000]
        # Stress the projected HP through the setup interval. Keep monsters in
        # their observed cells for the subsequent scan; movement is uncertain.
        for i in s['a']:
            for arrival,mid,damage,_,_ in reachable_wave(f,i,plan['seconds']):
                interval=max(.2,attack_delays().get(f['m'][mid][2],1000)/1000)
                s['a'][i][6]=max(0,s['a'][i][6]-damage*(1+int((plan['seconds']-arrival)/interval)))
            cover=list(s['cover'][i])
            name={448:'yuno_fild07',450:'yuno_fild09'}[a[3]]
            # Never grant visibility from an old position after the healer walks.
            cover[0]=attack_distance(name,pos(s['a'][s.get('healer',P)]),pos(s['a'][i]),9,0)==0
            s['cover'][i]=cover
        p=Planner(model);p.first_tick=first;p.return_seen=returned
        after=p.think(s,w)
        counts['proposals']+=1
        if after['safe']:counts['full_policy_permits']+=1
        for reason in after['reason']:counts[reason]+=1
    return counts

if __name__=='__main__':
    model=json.loads(Path(sys.argv[1]).read_text())
    print(json.dumps({d.name:evaluate(d,model) for d in map(Path,sys.argv[2:])},indent=2))
