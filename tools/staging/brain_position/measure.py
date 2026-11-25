"""Summarize native events over fixed fixture windows. No policy is evaluated here."""
import gzip,json,re,sys
from pathlib import Path
from collections import Counter,defaultdict,deque
ids=(2000001,*range(95000000,95000005))
wizard,camp=95000002,95000004
rx=re.compile(r'B_(\w+) (.*)')
keep=set('BUILD GEAR MARK STOCK BOUND STOP REGROUP DEATH FRAME A AID PULLSTATE PULL HIT DELIVER FIELD END DONE COVERMOVE PROBE CLEAR M KILL CAST'.split())
def read(d):
    radius,field,role,rep,arm=d.name.split('-')
    pull=95000001 if role=='knight' else 95000000
    result=json.loads(next(d.glob('*.result')).read_text().splitlines()[-1])
    c=Counter();damage=Counter();sp=Counter();first={};last={};gear=defaultdict(list);build={};deaths=Counter();stops=[];stock=defaultdict(Counter)
    healing=defaultdict(Counter);marks={};side=None;active=False;orcs=set();maxorcs=0;segment=set();near=True;far=False;t=0;prev=None;released=True;hp={};aid={};actions=set();window=deque();peak=0;pending=None;heals=[];other=Counter()
    emergency='emergency' in d.parts;initial=None;end=None
    for l in gzip.open(next(d.glob('*.gz')),'rt',errors='replace'):
        m=rx.search(l)
        if not m or m[1] not in keep:continue
        k=m[1];v=m[2].split()
        if k=='MARK':
            side=v[0];marks[side]=list(map(int,v[1:]));active=side=='start';continue
        if k=='STOCK' and side:stock[side][abs(int(v[1]))]+=int(v[2]);continue
        if k=='STOP':
            stops.append(v);continue
        if k=='CLEAR':c['clear']+=1;continue
        if k=='BUILD':
            n=list(map(int,v));build[n[1]]=n[2:];continue
        if k=='GEAR':
            n=list(map(int,v));gear[n[1]].append(n[2:]);continue
        if not active:continue
        if k=='PROBE':c['probe']+=1;continue
        if k=='FRAME':
            n=list(map(int,v));t=n[0];anchor=n[3:5];hp={};aid={};orcs.clear()
            if initial is None:initial=t
        elif k=='PULLSTATE':
            state=list(map(int,v));target=state[1] if not state[2] and not state[3] else 0
            if target:segment.add(target)
            else:
                if segment and actions.intersection(segment):c['pull_sequences']+=1
                segment.clear();actions.clear()
        elif k=='PULL':
            c['pull_actions']+=1;actions.add(int(v[2]))
        elif k=='A':
            a=list(map(int,v));i=a[1];hp[i]=a[6:10];first.setdefault(i,a[6:10]);last[i]=a[6:10]
            if i==pull:gap=max(abs(a[4]-anchor[0]),abs(a[5]-anchor[1]))
        elif k=='AID' and int(v[1])==camp:aid[int(v[2])]=list(map(int,v[3:]))
        elif k=='M' and emergency and v[2]=='1213':orcs.add(v[1])
        elif k=='DONE':
            assert set(hp)==set(ids) and set(aid)==set(ids)
            maxorcs=max(maxorcs,len(orcs));end=t
            if prev:
                pt,ph,pa=prev;dt=min(1,(t-pt)/1000);c['observed_s']+=dt
                for i,label in [(wizard,'wiz'),(pull,'pull'),(ids[0],'owner')]:
                    c[label+'_unreachable_s']+=dt*(not pa[i][0])
                    c[label+'_need_s']+=dt*(0<ph[i][0]<.7*ph[i][1])
                    c[label+'_unreachable_need_s']+=dt*(not pa[i][0] and 0<ph[i][0]<.7*ph[i][1])
                if not stops and ph[wizard][0]>0 and ph[camp][0]>0:
                    c['both_alive_pre_s']+=dt
                    c['wiz_out_before_stop_s']+=dt*(not pa[wizard][0])
                    if ph[wizard][0]<.7*ph[wizard][1]:
                        c['urgent_alive_pre_s']+=dt
                        c['urgent_out_pre_s']+=dt*(not pa[wizard][0])
                if stops:c['after_stop_s']+=dt
                c['dead_s']+=dt*any(x[0]==0 for x in ph.values())
            if hp[wizard][0]>0 and hp[wizard][0]<hp[wizard][1]*.7:
                if pending is None:pending=t
            elif pending is not None:
                other['death' if hp[wizard][0]==0 else 'recovered']+=1;pending=None
            prev=(t,hp,aid)
            outer=3 if radius=='6' else 8
            if gap>=outer and near and (segment or actions):far=True;near=False;c['outward']+=1
            if gap<=2:
                if far:c['returned']+=1
                far=False;near=True
        elif k=='HIT':
            n=list(map(int,v));i=n[2]
            if i in ids:
                sp[i]+=n[5]
                if n[1] not in ids and n[1]>0:
                    taken=min(n[4],n[6]);damage[i]+=taken
                    if i==wizard and taken:
                        while window and n[0]-window[0][0]>2000:window.popleft()
                        window.append((n[0],taken));peak=max(peak,sum(a[1] for a in window))
        elif k=='DEATH':deaths[int(v[1])]+=1
        elif k=='DELIVER':
            _,i,target,skill,h,shield=map(int,v)
            if i in ids and target in ids:
                s=healing[i]
                if skill==28 and h>0:
                    s['heal']+=1;s['restored']+=h
                    if target==wizard:
                        s['wiz_heal']+=1;s['wiz_hp']+=h
                        if pending is not None:heals.append((v[0],(int(v[0])-pending)/1000,i));pending=None
                if skill==73 and shield>0:s['kyrie']+=1;s['shield_capacity']+=shield
        elif k=='COVERMOVE':c['moves']+=1
        elif k=='CAST' and int(v[2])==54 and int(v[1]) in ids:c['raise']+=1
    if segment and actions.intersection(segment):c['pull_sequences']+=1
    assert marks['end'][::2]==marks['start'][::2] and len(build)==6
    supplies=stock['start'].copy();supplies.subtract(stock['end'])
    return dict(peak_wizard_2s=peak,heal_episodes=heals,heal_other=dict(other,open=int(pending is not None)),seconds=result['seconds'],base=marks['end'][1]-marks['start'][1],job=marks['end'][3]-marks['start'][3],SG=result['storm_fields'],tagged=result['tagged'],arrived=result['arrived'],anchor=result['anchor'],metrics=c,damage=damage,sp=sp,healing=healing,used={k:v for k,v in supplies.items() if v},deaths=deaths,stops=stops,build=build,gear=gear,first=first,last=last,maxorcs=maxorcs)
if __name__=='__main__':
    root=Path(sys.argv[1]);print(json.dumps({d.name:read(d) for d in sorted(root.iterdir())},indent=2))
