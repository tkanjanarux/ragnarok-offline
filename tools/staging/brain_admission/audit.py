"""Observe the native farm windows. Never credit a shadow vote as a departure."""
from collections import Counter,defaultdict
from pathlib import Path
import gzip,json,re,sys,tempfile
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'brain_stage2'))
from assess import check
from five_audit import measure

def measure_trip(d):
    audit=measure(d,True)
    trial=d.name.startswith('check-1')
    e=defaultdict(list);target={};opened=[];trip=0;start=False;anchor=None; tags={}; attacker=95000000 if d.name.endswith('priest') else 95000001
    frames=0; eligible=0; offered=0; pending=[];hp={};recovery=Counter();prev=None;stop_time=None;ordinary_wait=0;active_trip=False;violations=[]
    with gzip.open(next(d.glob('*.gz')),'rt') as f:
        for line in f:
            m=re.search(r'B_(\w+) (.*)',line)
            if not m:continue
            k,raw=m.groups()
            if k=='BOUND' and raw=='start':start=True
            if not start:continue
            if k=='MARK' and raw.startswith('end'):break
            v=[int(i) if i.lstrip('-').isdigit() else i for i in raw.split()]
            if k in ('STOP','REGROUP','HALTED','TRIP','TAG','PULL','TRIPEND','PEEL','COVERMOVE','APPROVAL','ADMITCHECK'):e[k].append(v)
            if k=='TRIP':trip=v[1];opened.append(v[0]);active_trip=True
            if k=='TRIPEND':active_trip=False
            if k=='STOP':stop_time=v[0];active_trip=False
            if k in ('PULL','TAG') and trial and not active_trip:violations.append((k,v))
            if k=='A':hp[v[1]]=v[6:8]
            if k=='DONE' and len(hp)==6:
                t=v[0]
                if prev and stop_time and prev>=stop_time:
                    dt=min(1,(t-prev)/1000)
                    recovery['after_stop_s']+=dt
                    if all(h>=.70*m for h,m in hp.values()):recovery['all_hp70_after_stop_s']+=dt
                prev=t
            if k=='OFFER':
                offered+=bool(v[1]);frames+=1
                ordinary_wait+=int(v[1]>0 and not v[2] and not stop_time)
            if k=='CAST' and v[1]==attacker and v[2]==6:pending.append(v)
            if k=='PULL' and pending and v[0]-pending[-1][0]<=5 and pending[-1][4]==v[2]:
                cv=pending.pop();key=(trip,v[1],v[2])
                out=target.setdefault(key,dict(orders=[],swing=[],cancel=[],damage=[],aggro=[],camp=None))
                out.setdefault('provoke',[]).append(cv[0]);out['orders'].append(cv[0]);tags[v[2]]=key
            if k=='FRAME':anchor=v[3:5]
            if k=='TAG':
                key=(v[1],v[2],v[3]);target.setdefault(key,dict(orders=[],swing=[],cancel=[],damage=[],aggro=[],camp=None))['orders'].append(v[0]);tags[v[3]]=key
            if k in ('SWING','ATKCANCEL','HIT','AGGRO','M'):
                mid=v[1] if k in ('AGGRO','M') else v[2]
                if mid in tags:
                    key=tags[mid];out=target[key];_,actor,mob=key
                    if v[0]<out['orders'][0]:continue
                    if k in ('HIT','SWING','ATKCANCEL') and v[1:3]==[actor,mob]:
                        if k=='HIT' and (v[3]!=0 or v[4]<=0):continue
                        out[{'SWING':'swing','HIT':'damage','ATKCANCEL':'cancel'}[k]].append(v)
                    if k=='AGGRO' and v[1]==mob and v[3]==actor:out['aggro'].append(v[0])
                    if k=='M' and v[1]==mob and out['aggro'] and anchor and max(abs(v[3]-anchor[0]),abs(v[4]-anchor[1]))<=2 and out['camp'] is None:out['camp']=v[0]
    plans=[json.loads(l) for l in (d/'decisions.jsonl').read_text().splitlines()]
    misses=[]
    if opened:
        votes=[p for p in plans if 'safe' in p];idx=({v[1] for v in e['APPROVAL']} if e['APPROVAL'] else {max(p['t'] for p in votes if p['t']<=t and p['safe']) for t in opened})
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'permissions.jsonl'
            with p.open('w') as f:
                for row in plans:
                    if 'safe' in row:row['safe']=row['t'] in idx
                    f.write(json.dumps(row)+'\n')
            misses=check(next(d.glob('*.gz')),p)['misses']
    return dict(out_of_trip=violations,wait_candidate_frames=ordinary_wait,observed_frames=frames,recovery=recovery,final_hp=hp,seconds=audit['seconds'],base=audit['base'],job=audit['job'],deaths=audit['native_deaths'],sp=audit['sp_debit'],supplies=audit['used'],camp_support=audit['delivered'],events=e,targets={str(k):v for k,v in target.items()},critical_after_grant=misses,shadow_yes=sum(bool(p.get('safe')) for p in plans))
if __name__=='__main__':
    print(json.dumps({d.name:measure_trip(d) for d in sorted(Path(sys.argv[1]).iterdir())},indent=2))
