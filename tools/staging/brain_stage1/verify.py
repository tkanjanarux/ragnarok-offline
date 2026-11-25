"""Reconcile native events with boundary readings. Uses only the measured window."""
from collections import Counter
from pathlib import Path
from bisect import bisect_right
import gzip,json,re,sys

def verify(path):
    frames=[]
    frame=None
    marks={}
    counts=Counter()
    deaths=Counter()
    mortality=[]
    gains=[0,0]
    exp_distance=Counter()
    fields_seen={}
    finished=[]
    last_cast={}
    examples=[]
    source=Path(str(path).replace('.log.gz','.result'))
    ledger=json.loads(next(l[7:] for l in source.read_text().splitlines() if l.startswith('LEDGER ')))
    result=json.loads(source.read_text().splitlines()[-1])
    control=None
    times=Counter()
    reading=None
    active=False
    with gzip.open(path,'rt',errors='replace') as f:
        for line in f:
            match=re.search(r'\bB_([A-Z]+) (.*)',line)
            if not match:continue
            k,fields=match.groups()
            fields=fields.split()
            if k=='MARK':
                reading=fields[0]
                marks[reading]=dict(xp=list(map(int,fields[1:])),stock=Counter(),dead={},pos={})
                active=False
                continue
            if k=='BOUND':
                active=reading=='start'
                reading=None
                continue
            a=list(map(int,fields))
            if reading:
                m=marks[reading]
                if k=='STOCK':m['stock'][tuple(a[:2])]=a[2]
                if k=='COUNTER':
                    m['dead'][a[0]]=a[1]
                    m['pos'][a[0]]=a[2:]
                if k=='INDEX':m['index']=a[0]
                continue
            if not active:continue
            counts[k]+=1
            if k=='CONTROL':
                control=a
            if k=='DEATH':
                deaths[a[1]]+=1
                ox,oy=marks['start']['pos'][2000001]
                mortality.append([a[0],a[1],max(abs(a[4]-ox),abs(a[5]-oy))])
            if k=='EXP' and a[1]==2000001:
                gains=[gains[0]+a[2],gains[1]+a[3]]
                if a[2] and len(a)==7 and a[4]:
                    ox,oy=marks['start']['pos'][2000001]
                    distance=max(abs(a[5]-ox),abs(a[6]-oy))
                    exp_distance[distance]+=a[2]
            if k=='CAST':
                last_cast[a[1],a[2]]=a
            if k=='FIELD':
                cast=last_cast.get((a[2],a[3]))
                if cast and cast[3]==a[4] and cast[5:7]==a[5:7] and 0<=a[0]-cast[0]<=max(2000,cast[7]+1500):
                    fields_seen[a[1]]=(cast,a)
            if k=='END' and a[1] in fields_seen:
                cast,birth=fields_seen.pop(a[1])
                finished.append(dict(actor=cast[1],skill=cast[2],level=cast[3],cast_ms=cast[0],field_ms=birth[0],end_ms=a[0],group=a[1]))
            if k=='FRAME':
                frame=dict(t=a[0],actors={},cover={},priest=a[7])
                frames.append(frame)
            if k=='A' and frame:frame['actors'][a[1]]=a
            if k=='COVER' and frame:frame['cover'][a[1]]=a
            if k in ('CAST','WALK','CHASE','CANCEL') and a[1] in range(95000000,95000004):
                if len(examples)<12:examples.append([k,*a])
    first,last=marks['start'],marks['end']
    assert first['xp'][::2]==last['xp'][::2], 'level transition needs rollover accounting'
    assert gains==[last['xp'][i]-first['xp'][i] for i in (1,3)]
    assert set(first['dead'])==set(last['dead'])=={2000001,95000000,95000001,95000002,95000003}
    assert all(deaths[i]==v-first['dead'][i] for i,v in last['dead'].items())
    changes=Counter()
    stockdist=Counter()
    ticks=[f['t'] for f in frames]
    for row in ledger:
        seq,profile,item,delta,*stamp=row
        if first['index']<seq<=last['index']:
            changes[profile,item]+=delta
            if stamp and frames:
                ix=bisect_right(ticks,stamp[0])-1
                if ix>=0 and stamp[0]-ticks[ix]<=1000:
                    actor=frames[ix]['actors'].get(94999999+profile)
                    if actor:
                        ox,oy=first['pos'][2000001]
                        stockdist[max(abs(actor[4]-ox),abs(actor[5]-oy))]-=delta
    for key in set(changes)|set(first['stock'])|set(last['stock']):
        assert changes[key]==last['stock'][key]-first['stock'][key],key
    for f,n in zip(frames,frames[1:]):
        dt=n['t']-f['t']
        if dt>1000:
            times['gap']+=dt
            continue
        actor=f['actors'][95000000 if f['priest'] else 95000001]
        wiz=f['cover'][95000002]
        walking=bool(actor[12])
        reach=bool(wiz[2])
        times['covered_samples']+=dt
        if walking:times['puller_walk']+=dt
        if not reach:times['wizard_out_of_heal_reach']+=dt
        if not reach and walking:times['both']+=dt
        if reach and not all(wiz[3:7]):times['in_reach_gate_closed']+=dt
    return dict(frames=len(frames),events=counts,exps=gains,deaths=mortality,control=control,stock={str(k):v for k,v in changes.items() if v},time_ms=times,exp_by_distance=exp_distance,stock_by_distance=stockdist,sample=examples,finished_fields=finished,client_deaths=result['companion_deaths']+result['owner_deaths'],anchor=result['anchor'])
def gate(rows):
    controls=[r for r in rows if r['control']]
    assert len(controls)==1
    cal=controls[0]
    radius=cal['control'][-1]
    distances=[event[-1] for event in cal['deaths']]
    assert min(distances)<=radius<max(distances)
    assert cal['client_deaths']<len(distances)
    for metric in ('stock_by_distance','exp_by_distance'):
        assert all(any(sum(n for dist,n in r[metric].items() if (dist>radius)==outside)>0 for r in rows) for outside in (False,True)),metric
    assert all(r['events']['A']==r['frames']*5 and r['events']['COVER']==r['frames']*5 for r in rows)
    assert all(r['time_ms']['gap']==0 and r['events']['AGGRO'] and r['events']['CAST'] and r['events']['WALK'] for r in rows)
    assert any(r['events']['CANCEL'] for r in rows)
    assert any(r['finished_fields'] and r['events']['CELL'] for r in rows)
    assert any(r['time_ms']['wizard_out_of_heal_reach']>r['time_ms']['both']>0 for r in rows)

if __name__=='__main__':
    files=[Path(p) for p in sys.argv[1:] if p!='--gate']
    rows={p.name:verify(p) for p in files}
    if '--gate' in sys.argv:gate(list(rows.values()))
    print(json.dumps(rows,indent=2))
