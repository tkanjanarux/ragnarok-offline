"""Reconcile sampled train arrivals with each actually instantiated SG footprint."""
import csv
import gzip
import re
import sys
from pathlib import Path


def calculate(p):
    probes=set()
    pack=set()
    positions={}
    cells={}
    frames=[]
    casts=[]
    windows=[]
    groups=[]
    cancelled=set()
    tick=None
    puller=95000000 if 'priest' in p.name else 95000001
    for line in gzip.open(p,'rt'):
        m=re.search(r'\bB_(PROBE|PACK|FRAME|DONE|M|CELL|END|CAST|CANCEL|WINDOW|FIELD) (.*)',line)
        if not m:continue
        k,raw=m.groups()
        if k=='PROBE' and not raw.strip().isdigit():continue
        v=list(map(int,raw.split()));t=v[0]
        if k=='PROBE':probes.add(t)
        elif k=='FRAME':pack=set();positions={};tick=t
        elif k=='PACK':pack.add(v[1])
        elif k=='M' and v[1] in probes:positions[v[1]]=tuple(v[3:6])
        elif k=='DONE' and t==tick:frames.append((t,dict(positions),pack.copy()))
        elif k=='CAST' and v[1:3]==[95000002,89]:casts.append((t,v[5],v[6]))
        elif k=='CANCEL' and v[1:3]==[95000002,89] and casts:cancelled.add(casts[-1][0])
        elif k=='WINDOW':windows.append(v)
        elif k=='CELL':cells.setdefault(v[1],set()).update((x,y) for x in range(v[2]-v[4],v[2]+v[4]+1) for y in range(v[3]-v[4],v[3]+v[4]+1))
        elif k=='FIELD' and v[2:4]==[95000002,89]:
            cs=[stamp for stamp,x,y in casts if (x,y)==tuple(v[5:7]) and stamp not in cancelled]
            if cs:groups.append([cs[-1],t,t+v[7],v[1],tuple(v[5:7])])
        elif k=='END':
            for g in groups:
                if g[3]==v[1]:g[2]=min(g[2],t)
    rows=[]
    for cast,start,end,gid,at in groups:
        estimates=[v for v in windows if cast<=v[0]<start and tuple(v[1:3])==at and v[3]==1 and v[4]>0]
        if not estimates:continue
        est=estimates[0]
        prev=[(t,ps,pack) for t,ps,pack in frames if t<=est[0]]
        if not prev:continue
        _,ps,pack=prev[-1]
        cohort={i for i in pack & ps.keys() if ps[i][2]==puller}
        if not cohort:continue
        first={}
        footprint=cells[gid]
        for mid in cohort:
            if ps[mid][:2] in footprint:first[mid]=est[0]
        for t,ps,_ in frames:
            if est[0]<=t<end:
                for mid in cohort & ps.keys():
                    if ps[mid][:2] in footprint:first.setdefault(mid,t)
        # Arrivals after the field expires are intentionally right-censored.
        observed=[t-est[0] for t in first.values()]
        rows.append(dict(run=p.parent.name,group=gid,forecast_tick=est[0],x=at[0],y=at[1],
                    forecast_count=est[4],matched_chasing=len(cohort),arrivals_seen=len(first),
                    predicted_head_ms=est[5],predicted_tail_ms=est[6],sampled_head_ms=min(observed) if observed else '',
                    sampled_tail_ms=max(observed) if len(observed)==len(cohort) else '',
                    cast_to_field_ms=start-cast,life_ms=end-start))
    return rows


if __name__=='__main__':
    root=Path(sys.argv[1])
    rows=[r for version in ('v9','v10') for p in sorted(root.glob(version+'-09-*/*.gz')) for r in calculate(p)]
    with (root/'arrival.csv').open('w') as out:
        w=csv.DictWriter(out,fieldnames=rows[0]);w.writeheader();w.writerows(rows)
