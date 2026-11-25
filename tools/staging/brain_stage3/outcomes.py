"""Evaluate native actions and EXP on the whole fixed clock, including fallback."""
import gzip,json,re,sys,tempfile
from collections import Counter
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'brain_stage2'))
from assess import check,episodes
from five_audit import measure
from planner import CAMP,OWNER,P,K,W,H,RX,dist

def evaluate(folder,emergency):
    trial=emergency or folder.name.startswith('check-1-')
    audit=measure(folder,True)
    path=next(folder.glob('*.gz'))
    rows=[json.loads(l) for l in (folder/'decisions.jsonl').read_text().splitlines()]
    intervals=Counter();previous=None;roster={};casts=set()
    first=rows[0]['t'];last=rows[-1]['t'];stops=[];halts=[];applied=[];regroup=None;timeline=[]
    health={};awards=[];native_pulls=[]
    # These are actual map-clock positions; five_audit independently verifies party membership.
    start=False
    with gzip.open(path,'rt',errors='replace') as log:
        for line in log:
            m=RX.search(line)
            if not m:continue
            k,raw=m.groups();v=raw.split()
            if k=='STOP':stops.append((int(v[0]),v[1],int(v[2])))
            if k=='REGROUP':regroup=int(v[0])
            if k=='HALTED':halts.append(list(map(int,v)))
            if k=='APPLY':applied.append((int(v[0]),v[1],*map(int,v[2:])))
            if k=='BOUND' and v==['start']:start=True
            if k=='MARK' and v[0]=='end':break
            if not start:continue
            if k=='FRAME':
                roster={};casts=set();t=int(v[0]);anchor=tuple(map(int,v[3:5]));pull=P if int(v[7]) else K
            if k=='A':
                vals=list(map(int,v));actor=vals[1];health[actor]=vals[6:8];roster[actor]=vals[6:8]
                if vals[16]:casts.add(vals[14])
                if actor==pull:timeline.append((t,tuple(vals[4:6])))
            if k=='DONE' and len(roster)==6:
                flags=dict(kyrie_cast=73 in casts,heal_cast=28 in casts,low_hp=any(hp*100<70*mx for hp,mx in roster.values()),
                           dead=any(hp==0 for hp,mx in roster.values()))
                if previous:
                    prev,old=previous
                    dt=min(1,(t-prev)/1000)
                    intervals['observed']+=dt
                    for flag,on in old.items():intervals[flag]+=on*dt
                previous=t,flags
            if k=='EXP' and int(v[1])==OWNER:awards.append((int(v[0]),int(v[2])))
            if k=='PULL':native_pulls.append(int(v[0]))
    assert len(stops)<=1
    cutoff=stops[0][0] if stops else float('inf')
    if stops:
        assert regroup is not None and all(a[0]<cutoff for a in applied)
        assert len(halts)==5 and all(a[2:]==[0,0] for a in halts)
        assert not any(t>regroup for t in native_pulls)
    within=[a for a in applied if first<=a[0]<=last]
    steps=[a for a in within if a[1]=='step'];confirmed=sum(any(p==tuple(a[3:5]) for t,p in timeline if a[0]<t<=a[0]+1000) for a in steps)
    gmax=max(dist(p,anchor) for t,p in timeline if t<=max(first,cutoff))
    bytime=dict(timeline)
    outward=0
    if trial:
        # An issued outbound lease remains accountable even when later revoked.
        with tempfile.TemporaryDirectory() as tmp:
            decisions=Path(tmp)/'decisions.jsonl'
            with decisions.open('w') as f:
                for row in rows:
                    if 'safe' in row:
                        op,x,y,_=row['lease'];t=row['t']
                        row['safe']=bool(t<cutoff and row['safe'] and (op==2 or (op==1 and dist((x,y),anchor)>dist(bytime[t],anchor))))
                        outward+=row['safe']
                    f.write(json.dumps(row)+'\n')
            assessed=check(path,decisions)
            misses=list({(e['t'],e['actor']):e for e in assessed['misses']}.values())
        heals,censors=assessed['episodes'],assessed['censored']
    else:
        misses=[]
        heals,censors=episodes(path,{r['t']:r for r in rows if 'team' in r})
    c=Counter(a[1] for a in within);cycles=0;outside=False
    for t,p in timeline:
        if t>=cutoff:break
        gap=dist(p,anchor)
        if gap<=1 and outside:cycles+=1;outside=False
        if gap>=3:outside=True
    return dict(wall=audit['seconds'],base=audit['base'],job=audit['job'],used=audit['used'],sp=audit['sp_debit'],
        gross_owner_base_before_stop=sum(b for t,b in awards if t<cutoff),
        gross_owner_base_after_stop=sum(b for t,b in awards if t>=cutoff),camp_deliveries=audit['delivered'],
        heal_actual_s=[h['actual'] for h in heals],heal_within=sum(h['pred'] is not None and h['actual']<=h['pred'] for h in heals),
        heal_unresolved_over_bound=sum(h['end']=='death' or (h['pred'] is not None and h['actual']>h['pred']) for h in censors),
        heal_no_forecast=sum(h['pred'] is None for h in heals+censors),heal_other=Counter(h['end'] for h in censors),observed_seconds=intervals,native_deaths=audit['native_deaths'],all_six_frames=audit['frames'],applied=c,step_confirmed=confirmed,
        native_outbound=len(native_pulls),max_gap_before_stop=gmax,short_cycles=cycles,
        issuer_outbound=outward,critical_after_authorization=misses,stop=stops,regroup_ms=regroup-cutoff if stops else None,
        seconds_before_stop=round(max(0,min(cutoff,last)-first)/1000,3),final_hp=health,max_orcs=audit['max_orcs'])
if __name__=='__main__':
    root=Path(sys.argv[1]);print(json.dumps({d.name:evaluate(d,root.name=='emergency') for d in sorted(root.glob('check-*/'))},indent=2))
