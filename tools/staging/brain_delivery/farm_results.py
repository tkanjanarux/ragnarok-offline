"""Paired, whole-window native-farm measurements; one row per arm, no exclusions."""
import csv
import gzip
import importlib.util
import json
import re
import sys
from collections import Counter
from pathlib import Path


def position_reader():
    path=Path(__file__).resolve().parents[1]/'brain_position/measure.py'
    spec=importlib.util.spec_from_file_location('position_measure',path)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.read


def field_counts(d):
    active=False
    groups={}
    bounds={}
    stocks={}
    events=Counter()
    probe=re.compile(r'\bB_(MARK|STOCK|FIELD|END|HIT|FRAME|A|M|PACK|DONE|BUILD|GEAR|DOCK|INVALID|STOP) (.+)')
    tank=95000000 if 'priest' in d.name else 95000001
    actors={}
    monsters={}
    pack=set()
    rear={2000001,95000002,95000003,95000004}
    before=0
    risk=set()
    dwells=set()
    coords=set()
    near_ms=0
    retreat=False
    retreat_ms=0
    first_retreat_tick=None
    for line in gzip.open(next(d.glob('*.gz')),'rt'):
        if active and 'Mob wizard ' in line and ' retreat=' in line:
            retreat=' retreat=1 ' in line
            if retreat and first_retreat_tick is None:first_retreat_tick=before
            continue
        m=probe.search(line)
        if not m:continue
        kind,raw=m.groups()
        if kind=='MARK':
            mark=raw.split()[0]
            active=mark=='start';stocks[mark]={}
            continue
        if kind=='STOCK':
            pid,item,qty=map(int,raw.split())
            stocks[mark][f'{pid}.{item}']=qty
        if not active or kind in ('BUILD','GEAR','STOCK','STOP'):continue
        v=list(map(int,raw.split()));t=v[0]
        if kind=='FRAME':
            near_ms+=min(1000,t-before)*bool(dwells) if before else 0
            retreat_ms+=min(1000,t-before)*retreat if before else 0
            before=t;dwells=set();pack=set()
        elif kind=='A':actors[v[1]]=v[4:6]
        elif kind=='M':monsters[v[1]]=v[3:6]
        elif kind=='PACK':pack.add(v[1])
        elif kind=='DONE':
            for mid in pack & monsters.keys():
                x,y,target=monsters[mid]
                if target==tank and any(max(abs(x-actors[r][0]),abs(y-actors[r][1]))<=2 for r in rear if r in actors):
                    dwells.add(mid);risk.add(mid)
        elif kind=='FIELD' and v[2:4]==[95000002,89]:
            groups[v[1]]=0;bounds[v[1]]=[t,t+v[7]]
            coords.add(tuple(v[5:7]))
        elif kind=='END' and v[1] in groups:bounds[v[1]][1]=min(bounds[v[1]][1],t)
        elif kind=='HIT' and v[1]==95000002 and v[3]==89 and v[4]>0:
            live=[gid for gid,(start,end) in bounds.items() if start<=t<end]
            if len(live)==1:groups[live[0]]+=1
        elif kind=='INVALID':events['invalid']+=1
        elif kind=='DOCK':events['dock']+=1
    return dict(field_hits=sum(groups.values()),empty=sum(not h for h in groups.values()),fields=len(groups),
                centers=sorted(coords),chasers_near=len(risk),rear_s=round(near_ms/1000,2),
                retreat_s=round(retreat_ms/1000,2),retreat_at_end=retreat,first_retreat_tick=first_retreat_tick,start_stock=stocks['start'],end_stock=stocks['end'],**events)


def save_csv(path,rows):
    with path.open('w') as out:
        writer=csv.DictWriter(out,fieldnames=rows[0])
        writer.writeheader();writer.writerows(rows)


def main(root):
    read=position_reader()
    runs={}
    data=[]
    for d in sorted((root/'farm').iterdir()):
        v=read(d);f=field_counts(d)
        v['field_measure']=f;runs[d.name]=v
        m=v['metrics']
        _,field,role,rep,arm=d.name.split('-')
        data.append(dict(field=field,puller=role,round=rep,arm=arm,seconds=v['seconds'],base=v['base'],
            per10=round(v['base']*600/v['seconds']),deaths=sum(v['deaths'].values()),stops=len(v['stops']),
            dead_s=round(m['dead_s'],2),unrecovered=int(bool(v['stops'] or f['retreat_at_end'] or any(h[0]==0 for h in v['last'].values()))),native_retreat_s=f['retreat_s'],
            damage=sum(v['damage'].values()),wizard_damage=v['damage'][95000002],
            pull_wounded_out_s=round(m['pull_unreachable_need_s'],1),wiz_wounded_out_s=round(m['wiz_unreachable_need_s'],1),
            chasers_near=f['chasers_near'],rear_s=f['rear_s'],fields=f['fields'],empty=f['empty'],field_hits=f['field_hits'],
            sp=sum(v['sp'].values()),gem=v['used'].get(717,0),arrows=sum(v['used'].get(i,0) for i in (1750,1754)),
            supplies=json.dumps(v['used'],sort_keys=True)))
    pairs=[]
    for n in sorted(runs):
        if not n.endswith('-native'):continue
        a=runs[n];b=runs[n.replace('-native','-delivery')]
        builds_same=all(a['build'][k][:3]==b['build'][k][:3] and a['build'][k][-2:]==b['build'][k][-2:] for k in a['build'])
        ga={k:sorted(v) for k,v in a['gear'].items()};gb={k:sorted(v) for k,v in b['gear'].items()}
        sa,sb=[r['field_measure']['start_stock'] for r in (a,b)]
        pairs.append(dict(pair=n.removesuffix('-native'),native_base=a['base'],delivery_base=b['base'],
            delta_base=b['base']-a['base'],delta_per10=round(600*(b['base']/b['seconds']-a['base']/a['seconds'])),
            same_job_level_skills=builds_same,same_equipped=ga==gb,same_site=a['anchor']==b['anchor'],
            different_start_stock=json.dumps({i:[sa.get(i,0),sb.get(i,0)] for i in sa.keys()|sb.keys() if sa.get(i,0)!=sb.get(i,0)})))
    (root/'farm-events.json').write_text(json.dumps(runs,indent=2)+'\n')
    save_csv(root/'farm-runs.csv',data);save_csv(root/'farm-pairs.csv',pairs)


if __name__=='__main__':main(Path(sys.argv[1]))
