"""Record actual danger *after* the native retreat latch in the small exit probe."""
import csv
import gzip
import re
import sys
from pathlib import Path


def read(d):
    side=95000000 if 'priest' in d.name else 95000001
    mark=None;last=0;damage=restored=exp=stop=deaths=0
    pack=set();mobs={};escort=set();losses=set();positions={}
    reachable=False
    help_ms=0
    seen=set()
    end=None
    for line in gzip.open(next(d.glob('*.gz')),'rt'):
        m=re.search(r'\bB_(FAULT|EXP|DELIVER|STOP|HIT|A|M|PACK|DONE|FRAME|AID|DEATH|MARK|DOCK) (.+)',line)
        if not m:continue
        kind,raw=m.groups()
        if kind=='MARK':
            if raw.startswith('end'):break
            continue
        if kind=='FAULT' and ' retreat ' in raw:
            mark=int(raw.split()[0]);last=mark
            continue
        if mark is None:continue
        if kind=='STOP':stop+=1;continue
        v=list(map(int,raw.split()));t=v[0]
        if kind=='FRAME':
            help_ms+=min(1000,max(0,t-last))*reachable
            last=t;pack=set();mobs={};end=t
        elif kind=='M':mobs[v[1]]=v[3:6]
        elif kind=='A':positions[v[1]]=v[4:6]
        elif kind=='PACK':pack.add(v[1])
        elif kind=='AID' and v[1]==95000004 and v[2]==side:reachable=bool(v[3])
        elif kind=='DONE':
            escort={i for i in pack if i in mobs and mobs[i][2]==side}
            for i in escort:
                x,y,_=mobs[i]
                if any(max(abs(x-positions[r][0]),abs(y-positions[r][1]))<=2 for r in (2000001,95000002,95000003,95000004)):seen.add(i)
        elif kind=='HIT' and v[2]==side and v[1]>0 and v[1] not in positions:damage+=v[4]
        elif kind=='DELIVER' and v[2]==side and v[3]==28:restored+=v[4]
        elif kind=='EXP' and v[1]==2000001:exp+=v[2]
        elif kind=='DEATH':deaths+=1
    return dict(run=d.name,triggered=mark is not None,after_ms=end-mark if end and mark else 0,base_after=exp,
                hp_damage=damage,heal_delivered=restored,healer_reach_ms=help_ms,
                chasing_at_end=len(escort),chasers_near_backline=len(seen),deaths=deaths,critical_stops=stop,
                last_puller=positions.get(side))

if __name__=='__main__':
    root=Path(sys.argv[1]);rows=[read(d) for d in sorted(root.glob('exit-*'))]
    with (root/'exit.csv').open('w') as f:
        w=csv.DictWriter(f,fieldnames=rows[0]);w.writeheader();w.writerows(rows)
