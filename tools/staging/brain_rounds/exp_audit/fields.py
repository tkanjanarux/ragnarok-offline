"""Attribute effects by live skill group, exact victim and lethal damage."""
import gzip
import re
import sys
from pathlib import Path
from analyze import save
def fields(d):
    active=False;pending=None;groups={};all_rows=[];probe=set();dead={};first_hit=None;secure=None;marks=[];t=0;round_start=None;cluster=None
    for line in gzip.open(next(d.glob('*.gz')),'rt'):
        m=re.search(r'B_(MARK|CLUSTER|ROUND|SECURE|CAST|FIELD|CANCEL|END|KILL|HIT|PROBE) (.*)',line)
        if not m:continue
        key,v=m[1],m[2].split()
        if key=='MARK':active=v[0]=='start';marks.append(v);continue
        if key=='PROBE' and v[0].isdigit():probe.add(int(v[0]));continue
        if key=='ROUND' and int(v[2])==1 and round_start is None:round_start=int(v[0])
        if not active:continue
        n=list(map(int,v));t=n[0]
        if key=='ROUND':continue
        elif key=='CLUSTER':cluster=n
        elif key=='CAST' and n[1:3]==[95000002,89]:pending=(t,n,cluster)
        elif key=='CANCEL' and n[1:3]==[95000002,89]:pending=None
        elif key=='FIELD' and n[2:4]==[95000002,89]:
            r=dict(run=d.name,group=n[1],cast_ms=pending[0] if pending else None,field_ms=t,level=n[4],x=n[5],y=n[6],end_ms=t+n[7],
                   forecast_cast_ms=pending[1][-1] if pending else None,cluster_at_cast=pending[2][2] if pending and pending[2] else None,
                   hits=0,victims=set(),damage=0,lethal=0)
            pending=None;groups[n[1]]=r;all_rows.append(r)
        elif key=='END' and n[1] in groups:groups.pop(n[1])['end_ms']=t
        elif key=='HIT' and n[4]>0:
            if n[2] in probe and first_hit is None:first_hit=t
            if n[1]==95000002 and n[3]==89:
                live=[r for r in groups.values() if t<r['end_ms']]
                assert len(live)==1
                r=live[0];r['hits']+=1;r['victims'].add(n[2]);r['damage']+=min(n[4],n[6]);r['lethal']+=n[4]>=n[6]
        elif key=='KILL' and n[1] in probe:dead[n[1]]=t
        elif key=='SECURE' and dead and secure is None:secure=t
    for r in all_rows:r['victims']=len(r['victims'])
    last=max(dead.values()) if dead else None
    return all_rows,dict(run=d.name,placed=len(probe),killed=len(dead),opening_level=all_rows[0]['level'] if all_rows else None,
                         first_hit=first_hit,last_death=last,first_to_last_s=(last-first_hit)/1000 if last and first_hit else None,
                         depart_to_last_s=(last-round_start)/1000 if last and round_start else None,secure=secure,exp=int(marks[-1][2])-int(marks[0][2]))
if __name__=='__main__':
    rows=[];cases=[]
    for d in sorted(p for p in Path(sys.argv[1]).iterdir() if p.is_dir()):
        fs,c=fields(d);rows+=fs;cases.append(c)
    out=Path(sys.argv[2]);save(out/'fields.csv',rows);save(out/'field-runs.csv',cases)
