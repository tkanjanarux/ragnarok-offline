"""Measure the former reception area on the eight archived native radius-96 traces."""
import csv
import gzip
from pathlib import Path
import sys

src,dst=map(Path,sys.argv[1:])
rows=[]
for path in sorted(src.glob('96-*-native/*.gz')):
    puller=95000000 if 'priest' in path.name else 95000001
    counts=dict(sg_fields=0,on_anchor=0,sg_positive_hits=0)
    camp=None
    monsters={}
    actors={}
    pack=set()
    rear=set()
    train=set()
    for line in gzip.open(path,'rt'):
        if 'B_' not in line:continue
        kind,_,raw=line.partition('B_')[2].partition(' ')
        if kind not in ('FRAME','FIELD','HIT','PACK','M','A','DONE'):continue
        v=list(map(int,raw.split()))
        if kind=='FRAME':camp=v[3:5];pack=set()
        elif kind=='FIELD' and v[2:4]==[95000002,89]:
            counts['sg_fields']+=1;counts['on_anchor']+=v[5:7]==camp
        elif kind=='HIT':
            counts['sg_positive_hits']+=v[1]==95000002 and v[3]==89 and v[4]>0
        elif kind=='PACK':pack.add(v[1])
        elif kind=='M':monsters[v[1]]=(v[3],v[4],v[5])
        elif kind=='A':actors[v[1]]=v[4:6]
        elif kind=='DONE':
            for mid in pack & monsters.keys():
                x,y,target=monsters[mid]
                if target!=puller:continue
                train.add(mid)
                if any(max(abs(x-ax),abs(y-ay))<=2 for a,(ax,ay) in actors.items() if a in (2000001,95000002,95000003,95000004)):rear.add(mid)
    rows.append(dict(run=path.parent.name,anchor_x=camp[0],anchor_y=camp[1],**counts,unique_chasers=len(train),chased_near_backline=len(rear)))
with dst.open('w') as out:
    writer=csv.DictWriter(out,fieldnames=rows[0]);writer.writeheader();writer.writerows(rows)
