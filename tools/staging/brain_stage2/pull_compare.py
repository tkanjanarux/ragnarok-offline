"""Compare observational authorizations with native outbound-target, movement and departures."""
import json,sys
from collections import Counter
from pathlib import Path
from planner import World,readlog,pos,dist,K

def compare(d):
    decisions={v['t']:v for l in (d/'decisions.jsonl').read_text().splitlines() if 'team' in (v:=json.loads(l))}
    times=list(decisions); c=Counter(); starts=[];last_command=-10000;ready=True;last_near=None
    last=None
    for typ,f in World().frames(readlog(next(d.glob('*.log.gz')),False)):
        if typ=='pull':
            last_command=f[0];c['native_actions']+=1
            continue
        if typ!='frame':continue
        t=f['t'];actor=f['a'][f['pull']];gap=dist(pos(actor),f['anchor'])
        if gap<=4:ready=True;last_near=t
        if ready and gap>=6 and last_near is not None and t-last_command<=5000 and not f['inbound']:
            # A permission must predate (or coincide with) the outward crossing.
            nearby=[v for ts,v in decisions.items() if t-2500<=ts<=t]
            starts.append([t,any(v['safe'] for v in nearby)])
            ready=False
        if t not in decisions:continue
        v=decisions[t]
        native=bool(f['native_target'])
        moving=native and bool(actor[12] or t-last_command<=1000)
        script=v['team'][0 if f['pull']==K else 1]
        recommends=v['safe'] and (script in ('pull_short','self_pull') or (script=='production' and native))
        vals=dict(permit=v['safe'],recommended=recommends,native_intent=native,native_action=moving,
                  matching_intent=v['safe'] and native,matching_action=v['safe'] and moving)
        if last:
            dt=min(1000,t-last[0]);c['ms']+=dt
            for key,flag in last[1].items():c[key+'_ms']+=dt*flag
        last=t,vals
    c['starts']=len(starts);c['matched_starts']=sum(ok for _,ok in starts)
    return dict(counters=c,starts=starts)
if __name__=='__main__':
    by={p.name:compare(p) for p in map(Path,sys.argv[1:])};total=Counter()
    for r in by.values():total.update(r['counters'])
    print(json.dumps(dict(total=total,runs=by),indent=2))
