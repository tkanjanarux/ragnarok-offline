import gzip
import json
import re
import sys
from collections import Counter
from pathlib import Path

def read(folder):
    events=[];trained=set();second=set();add=None;t=None
    outcome=Counter();first=None;hits=[];transitions=[];waves=[];deaths=[];stops=[];aggro=[];fault=None;kills={};hp=Counter()
    for line in gzip.open(next(folder.glob('*.gz')),'rt'):
        match=re.search(r'B_(\w+) (.*)',line)
        if not match:continue
        key,raw=match.groups()
        if key in ('PROBE','NEXT','STRAY','ADD') and raw.isdigit():
            mid=int(raw)
            if key=='PROBE':trained.add(mid)
            elif key=='NEXT':second.add(mid)
            else:add=mid
            continue
        if key=='STOP':stops.append(raw);continue
        if key=='FAULT':fault=raw;continue
        if key not in ('HIT','KILL','ROUND','SECURE','AGGRO','FIELD','CAST','DEATH','PULL','SPELLEFFECT'):continue
        v=list(map(int,raw.split()));t=v[0]
        if key=='PULL' and v[2] in second:events.append(v)
        if key=='ROUND':transitions.append(v)
        if key=='DEATH':deaths.append(v)
        if key=='KILL':kills[v[1]]=v[0]
        if key=='FIELD' and v[2:4]==[95000002,89]:waves.append(v)
        if key=='AGGRO' and v[1]==add:aggro.append(v)
        if key=='HIT' and v[4]>0 and v[2]==add and 95000000<=v[1]<=95000004:hits.append(v[:5])
        if key=='HIT' and v[4]>0 and v[3]==89 and v[2] in trained:
            hp[v[2]]+=min(v[4],v[6])
    return dict(scenario=folder.name,add_id=add,first_hunter=next((v for v in hits if v[1]==95000003),None),
        first_wizard=next((v for v in hits if v[1]==95000002),None),add_last_hit=hits[-1] if hits else None,
        add_killed=kills.get(add),add_aggro=aggro,trained=len(trained),initial_kills=[kills.get(i) for i in sorted(trained)],
        second_kills=[kills.get(i) for i in sorted(second)],first_pull_second=next(iter(events),None),
        actual_sg_damage=hp,fields=waves,rounds=transitions,fault=fault,deaths=deaths,stops=stops)
if __name__=='__main__':
    root=Path(sys.argv[1])
    data={str(d.relative_to(root)):read(d) for name in ('final','challenges') for d in sorted((root/name).glob('probe-*')) if list(d.glob('*.gz'))}
    (root/'probe-events.json').write_text(json.dumps(data,indent=2)+'\n')
