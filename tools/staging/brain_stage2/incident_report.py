"""Inspect the state available at each safety forecast that later crossed its reserve."""
import json,sys
from pathlib import Path
from planner import TEAM,P,K,pos,dist,World,readlog

def incidents(d):
    result=json.loads((d/'check.json').read_text())
    misses={(m['actor'],m['t']):m for m in result['misses']}
    decisions={r['t']:r for l in (d/'decisions.jsonl').read_text().splitlines() if 'safe' in (r:=json.loads(l))}
    ticks={m['forecast'] for m in misses.values()};states={};first_orcs=None
    for kind,f in World().frames(readlog(next(d.glob('*.gz')),False)):
        if kind!='frame':continue
        orcs=[m for m in f['m'].values() if m[2]==1213]
        if len(orcs)>=5 and first_orcs is None:first_orcs=f['t']
        if f['t'] in ticks:
            t=f['t'];a=f['a'];s=decisions[t]
            states[t]={i:dict(orcs=len(orcs),hp=a[i][6],healer_gap=dist(pos(a[f.get('healer',P)]),pos(a[i])),guard_gap=dist(pos(a[K]),pos(a[i])),cover=f['cover'][i],reachable=s['reachable'].get(str(i)),help_eta=s['eta'][str(i)]) for i in a}
    return dict(first_wave_frame=first_orcs,misses=[dict(**m,state=states[m['forecast']][m['actor']],seconds_to_critical=round((m['t']-m['forecast'])/1000,3)) for m in misses.values()])
if __name__=='__main__':
    print(json.dumps({p.name:incidents(p) for p in map(Path,sys.argv[1:])},indent=2))
