"""Time without a replacement after explicit dock invalidation, inside the farm window."""
import csv
import gzip
import re
import sys
from pathlib import Path


def measure(d):
    kinds=re.compile(r'\bB_(DOCK|INVALID|FRAME|A|PACK|MARK|EXP) (.+)')
    active=False
    last=0
    dead=None
    record=None
    rows=[]
    state={}
    for line in gzip.open(next(d.glob('*.gz')),'rt'):
        m=kinds.search(line)
        if not m:continue
        k,raw=m.groups()
        if k=='MARK':
            active=raw.startswith('start')
            if not active and record:
                rows.append(dict(record,end=last,ms=max(0,last-dead),censored=True))
                record=None
            continue
        if not active:continue
        v=list(map(int,raw.split()));last=v[0]
        if k=='A':state[v[1]]=v[4:10]
        elif k=='FRAME' and record:
            record['samples']+=1
            if v[-1]:record['release_samples']+=1
        elif k=='EXP' and record and v[1]==2000001:record['owner_base_credit']+=v[2]
        elif k=='INVALID' and not record:
            dead=v[0]
            wx,wy=state.get(95000002,[None,None])[:2]
            hx,hy=state.get(95000004,[None,None])[:2]
            record=dict(run=d.name,start=dead,dock_x=v[1],dock_y=v[2],owner_x=v[3],owner_y=v[4],pull_x=v[5],pull_y=v[6],
                        wizard_x=wx,wizard_y=wy,priest_x=hx,priest_y=hy,samples=0,release_samples=0,owner_base_credit=0)
        elif k=='DOCK' and record:
            rows.append(dict(record,end=last,ms=max(0,last-dead),censored=False))
            record=None
    return rows


if __name__=='__main__':
    root=Path(sys.argv[1]);rows=[r for d in sorted((root/'farm').glob('*-delivery')) if list(d.glob('*.gz')) for r in measure(d)]
    with (root/'farm-invalid.csv').open('w') as f:
        w=csv.DictWriter(f,fieldnames=rows[0]);w.writeheader();w.writerows(rows)
