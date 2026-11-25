"""Classify the first observed close approach per mob in a real farm window."""
import csv
import gzip
import re
import sys
from pathlib import Path


def rows(d):
    pattern=re.compile(r'\bB_(MARK|DOCK|INVALID|M|A|PACK|FRAME|DONE) (.*)')
    active=False
    mobs={};actors={};pack=set();seen=set();initial={};out=[]
    dock=None;mode=None;anchor=None;tick=None
    puller=95000000 if 'priest' in d.name else 95000001
    for line in gzip.open(next(d.glob('*.gz')),'rt'):
        m=pattern.search(line)
        if not m:continue
        k,raw=m.groups()
        if k=='MARK':active=raw.startswith('start ');continue
        if k=='DOCK':
            i=list(map(int,raw.split()));dock=i[3:5];continue
        if k=='INVALID':dock=None;continue
        if not active:continue
        i=list(map(int,raw.split()))
        if k=='FRAME':tick=i[0];anchor=i[3:5];mode=i[-2:];pack=set();mobs={}
        elif k=='PACK':pack.add(i[1])
        elif k=='A':actors[i[1]]=i[4:6]
        elif k=='M':mobs[i[1]]=i[3:6]
        elif k=='DONE':
            for mid in pack & mobs.keys():
                x,y,who=mobs[mid]
                if who!=puller:continue
                ds=[(max(abs(x-actors[w][0]),abs(y-actors[w][1])),w) for w in (2000001,95000002,95000003,95000004)]
                gap,near=min(ds)
                initial.setdefault(mid,(tick,gap))
                if gap>2 or mid in seen:continue
                seen.add(mid)
                start,first_gap=initial[mid]
                out.append(dict(run=d.name,tick=tick,mob=mid,nearest=near,gap=gap,first_gap=first_gap,
                              since_first_chase_ms=tick-start,inbound=mode[0],released=mode[1],x=x,y=y,
                              near_x=actors[near][0],near_y=actors[near][1],tank_x=actors[puller][0],tank_y=actors[puller][1],
                              dock_x=dock[0] if dock else '',dock_y=dock[1] if dock else '',
                              anchor_x=anchor[0],anchor_y=anchor[1]))
    return out

if __name__=='__main__':
    root=Path(sys.argv[1])
    r=[e for d in sorted((root/'farm').iterdir()) if list(d.glob('*.gz')) for e in rows(d)]
    with (root/'farm-close.csv').open('w') as f:
        writer=csv.DictWriter(f,fieldnames=r[0]);writer.writeheader();writer.writerows(r)
