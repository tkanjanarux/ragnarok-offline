"""Read immutable farm logs. EXP is joined by mob instance, not a proximity window."""
import bisect
import csv
import gzip
import json
import re
import sys
from collections import Counter,defaultdict
from pathlib import Path

team={2000001,*range(95000000,95000005)}
wizard,hunter=95000002,95000003
rx=re.compile(rb'\bB_(\w+) (.*)')
def gap(a,b):return max(abs(a[0]-b[0]),abs(a[1]-b[1]))
def save(p,rs):
    if not rs:return
    with p.open('w') as f:
        w=csv.DictWriter(f,fieldnames=list(dict.fromkeys(k for r in rs for k in r)));w.writeheader();w.writerows(rs)

def analyze(d):
    _,field,role,rep,arm=d.name.split('-');pull=95000001 if role=='knight' else 95000000
    name=d.name;frames=[];phase=0;dock=None;stopped=False;active=False
    marks={};boundary={};last_tick=0;events=[];gates=[];first_party=set();levels={};bounds={};groups={}
    frame_skills=Counter()
    prev=None
    with gzip.open(next(d.glob('*.gz')),'rb') as f:
        for l in f:
            m=rx.search(l)
            if not m:continue
            k=m[1];v=m[2].split()
            if k==b'MARK':
                side=v[0].decode();marks[side]=list(map(int,v[1:]));active=side=='start'
                bounds[side]=[last_tick,None];continue
            if not v[0].isdigit() or int(v[0])<10**12:continue
            t=int(v[0]);last_tick=t
            for side,b in bounds.items():
                if b[1] is None:b[1]=t
            if k==b'BUILD':levels[int(v[1])]=list(map(int,v[2:5]))
            if k==b'PARTY':first_party.add((int(v[2]),int(v[3])))
            if k==b'ROUND':phase=int(v[2])
            if k==b'DOCK':dock=tuple(map(int,v[3:5]))
            if k==b'INVALID':dock=None
            if k==b'STOP':stopped=True
            if k==b'FRAME':
                ax=tuple(map(int,v[3:5]));ms={};actors={};pack=set();inbound=int(v[8]);rel=int(v[9]);target=0
            elif k==b'M':
                n=list(map(int,v[1:8]));ms[n[0]]=(n[1],(n[2],n[3]),n[4],n[5],n[6])
            elif k==b'A':
                n=list(map(int,v));actors[n[1]]=(tuple(n[4:6]),n[12],n[13],n[14],n[16],n[6],n[8])
            elif k==b'PACK':pack.add(int(v[1]))
            elif k==b'PULLSTATE':target=int(v[1])
            elif k==b'DONE':
                frame=(t,ax,dock,ms,actors,pack,bool(target and not rel),bool(inbound),phase,stopped,rel)
                if active:frames.append(frame)
                else:
                    if 'start' not in bounds:prev=frame
            if active and k in (b'KILL',b'EXP',b'HIT',b'FIELD',b'CAST',b'AGGRO',b'PULL',b'END'):
                events.append((k,*map(int,v)))
            if active and k==b'GATE':gates.append([t,*map(int,v[1:12]),b' '.join(v[12:]).decode()])
    start,end=[sum(bounds[s])/2 for s in ('start','end')]
    assert prev and start<frames[0][0] and frames[-1][0]<end
    frames=[(start,*prev[1:]),*frames]
    ts=[r[0] for r in frames];at=lambda t:max(0,bisect.bisect_right(ts,t)-1)
    # A trip starts on a newly selected outbound leg, not a switch between targets.
    trips=[];states=[];timeline=[];idx=[];preceding=False;seen_sg=False
    disappeared=[];contact={}
    for i,(t,a,dock,ms,actors,pack,outbound,inbound,phase,stop,rel) in enumerate(frames):
        out=outbound and not inbound
        if not trips or out and not preceding:
            trips.append(dict(run=name,trip=len(trips),actual_departure=bool(out),start_ms=round(t),end_ms=0,
                              pack_ids=set(),peak_pack=0,walk_cells=0,moving_s=0,pack_exits_alive=0,
                              kills=0,exp=0,sp_debit=0,stock_debits=Counter(),species_killed=Counter(),aggro_away=set(),sg_hits=0,sg_kills=0,fields=0,camp_ds=0,last_kill=0,first_kill=0))
            seen_sg=False
        preceding=out;tr=trips[-1];idx.append(len(trips)-1)
        tr['pack_ids'].update(pack);tr['peak_pack']=max(tr['peak_pack'],len(pack))
        nt=ts[i+1] if i+1<len(ts) else end
        dt=(nt-t)/1000;pos=actors[pull][0];meet=dock or a
        near=any(m in ms and gap(ms[m][1],meet)<=4 for m in pack)
        danger=any(v[2] in team and gap(v[1],a)<=7 for v in ms.values())
        if stop or phase==3:state='withdraw_recover'
        elif out:state='collect'
        elif (pack or inbound) and not near and gap(pos,meet)>4:state='return'
        elif pack and near and not seen_sg:state='handoff'
        elif pack or danger:state='finish'
        else:state='prepare' if len(trips)==1 and not tr['actual_departure'] else 'restart_wait'
        # Mark first SG hit in this leg using the actual hit time in postprocessing below.
        if i+1<len(ts):
            step=gap(pos,frames[i+1][4][pull][0]);tr['walk_cells']+=step
            if step:tr['moving_s']+=dt
            disappeared.extend((len(trips)-1,m,t,nt) for m in pack-frames[i+1][5] if m in frames[i+1][3] and frames[i+1][3][m][3]>0)
        tr['end_ms']=round(nt);states.append(state)
        timeline.append([i,t,nt,dt,state])
    last_hit={};sg_targets=set();sg_hp=0;ds_hp=0;add_sp=0;add_casts=0;last_cast={};kills=[];by_mob={};first_hits=set();mob_hits={};timed_fields={}
    first_sg={};add_events=[]
    for k,t,*v in events:
        i=at(t);tr=trips[idx[i]];ms=frames[i][3];a=frames[i][1]
        if k==b'AGGRO' and v[1]==pull and v[2]!=pull and v[0] in frames[i][5]:
            tr['aggro_away'].add(v[0])
        if k==b'HIT' and v[1] in team:tr['sp_debit']+=max(0,v[4])
        if k==b'CAST' and v[0] in (hunter,wizard):last_cast[v[0]]=(t,v[1],v[3])
        if k==b'HIT' and v[0]==0 and v[1] in last_cast and v[4]>0:
            # Only assign a debit when the same tick has an observed cast on a known camp add.
            tick,sk,mid=last_cast[v[1]]
            if tick==t and any(m==mid for _,m in add_events):add_sp+=v[4];add_casts+=1
        if k==b'HIT' and v[0] in team and v[2]>=0 and v[3]>0 and v[1] not in team:
            src,mid,skill,hit=v[:4];last_hit[mid]=(src,skill,t);mob_hits.setdefault(mid,[]).append((t,src,skill))
            if mid in frames[i][5] and mid in ms and gap(ms[mid][1],frames[i][2] or a)<=4:
                contact.setdefault(tr['trip'],t)
            if src==wizard and skill==89:
                tr['sg_hits']+=1;first_sg.setdefault(tr['trip'],t)
                sg_hp+=min(hit,v[5]);sg_targets.add((mid,len([x for x in kills if x['mob']==mid])))
            if mid not in first_hits:
                first_hits.add(mid)
                if src==hunter and skill==46 and mid in ms and gap(ms[mid][1],a)<=7 and ms[mid][2]==0:
                    tr['camp_ds']+=1;add_events.append((t,mid))
        elif k==b'FIELD' and v[1:3]==[wizard,89]:
            tr['fields']+=1;timed_fields[v[0]]=[t,t+v[6]]
        elif k==b'END' and v[0] in timed_fields:timed_fields[v[0]][1]=min(t,timed_fields[v[0]][1])
        elif k==b'EXP' and v[0]==2000001 and v[1]:
            kill=by_mob[v[3]];assert abs(kill['tick']-t)<50
            kill['exp']+=v[1]
        elif k==b'KILL':
            mid,kind,killer=v;hit=last_hit.get(mid)
            skill=hit[1] if hit and hit[0]==killer and abs(t-hit[2])<=10 else None
            kills.append(dict(run=name,trip=tr['trip'],tick=t,mob=mid,kind=kind,killer=killer,skill=skill))
            first_hits.discard(mid);last_hit.pop(mid,None)
            by_mob[mid]=kills[-1];by_mob[mid]['exp']=0
            tr['kills']+=1;tr['last_kill']=t;tr['first_kill']=tr['first_kill'] or t
            if skill==89:tr['sg_kills']+=1
    for k in kills:
        trips[k['trip']]['exp']+=k['exp'];trips[k['trip']]['species_killed'][k['kind']]+=1
    assert sum(k['exp'] for k in kills)==marks['end'][1]-marks['start'][1]
    seg=[];phases=Counter()
    for i,t,nt,dt,state in timeline:
        tr=trips[idx[i]]
        if state=='handoff' and min(first_sg.get(tr['trip'],end+1),contact.get(tr['trip'],end+1))<=t:state='finish'
        phases[state]+=dt
        if seg and seg[-1]['trip']==tr['trip'] and seg[-1]['state']==state:seg[-1]['end']=round(nt)
        else:seg.append(dict(run=name,trip=tr['trip'],state=state,start=round(t),end=round(nt)))
        if state=='collect' and not any(frames[i][4][wizard][j] for j in (1,2,4)) and not any(x<=t<y for x,y in timed_fields.values()):phases['wizard_wait_overlap']+=dt
        if state=='return' and not frames[i][4][pull][1]:phases['return_no_walktimer_overlap']+=dt
    for trip,mid,t,nt in disappeared:
        if not any(k['mob']==mid and t<=k['tick']<=nt for k in kills):trips[trip]['pack_exits_alive']+=1
    for line in next(d.glob('*.result')).read_text().splitlines():
        if line.startswith('LEDGER '):
            for _,profile,item,change,tick in json.loads(line[7:]):
                if start<=tick<end and change<0:trips[idx[at(tick)]]['stock_debits'][abs(item)]-=change
    for tr in trips:
        tr['aggro_away']=len(tr['aggro_away'])
        for key in ('stock_debits','species_killed'):tr[key]=json.dumps(tr[key],sort_keys=True)
        leg=[k['tick'] for k in kills if k['trip']==tr['trip']]
        tr['tail_gap_s']=round((leg[-1]-leg[-2])/1000,3) if len(leg)>=2 else ''
        tr['dock_contact_to_last_kill_s']=round((leg[-1]-contact[tr['trip']])/1000,3) if leg and tr['trip'] in contact and leg[-1]>=contact[tr['trip']] else ''
        tr['unique_pack']=len(tr.pop('pack_ids'));tr['moving_s']=round(tr['moving_s'],2)
        tr['first_to_last_kill_s']=round((tr['last_kill']-tr['first_kill'])/1000,2) if tr['kills'] else ''
        tr['cells_per_elapsed_s']=round(1000*tr['walk_cells']/(tr['end_ms']-tr['start_ms']),2)
    last=frames[-1];endpack=[(m,last[3][m][0],last[3][m][3]) for m in sorted(last[5]) if m in last[3]]
    init=frames[1];census=Counter(v[0] for v in init[3].values());prox=Counter(v[0] for v in init[3].values() if gap(v[1],init[1])<=96)
    pos=sorted((m,v[0],*v[1]) for m,v in init[3].items())
    import hashlib
    summary=dict(run=name,field=field,role=role,rep=rep,arm=arm,credited=sum(k['exp'] for k in kills),kills=len(kills),
                 mark_time_s=round((end-start)/1000,3),mark_brackets=bounds,party=sorted(first_party),levels=levels,
                 initial_census=census,initial_within96=prox,pos_digest=hashlib.sha256(str(pos).encode()).hexdigest(),endpack=endpack,
                 phases={k:round(n,2) for k,n in phases.items()},trips=sum(t['actual_departure'] for t in trips),camp_open_ds=add_events,
                 end_cohort_later={},sg_damage=sg_hp,sg_lives_hit=len(sg_targets),later_add_sp_matched=add_sp,later_add_sp_debits=add_casts)
    if gates:
        summary['gate_samples']=len(gates)
        summary['gate_native_yes_suppressed']=sum(r[3] and not r[5] for r in gates)
        summary['gate_reasons']=dict(Counter(r[-1] for r in gates if r[2] in (2,3)))
    return summary,trips,seg,kills,frames,events

if __name__=='__main__':
    directory,out=map(Path,sys.argv[1:]);out.mkdir(exist_ok=True)
    summaries=[];trips=[];segs=[];kills=[]
    for d in sorted(directory.iterdir()):
        s,tr,seg,ks,fr,ev=analyze(d)
        if directory.name=='extension':
            start=sum(s['mark_brackets']['start'])/2;cut=start+120000
            last=next(f for f in reversed(fr) if f[0]<=cut)
            s['exp_first120']=sum(k['exp'] for k in ks if k['tick']<=cut)
            s['end_cohort_later']={str(m):next(([k['exp'],round((k['tick']-cut)/1000,3)] for k in ks if k['tick']>cut and k['mob']==m),None) for m in last[5]}
        summaries.append(s);trips.extend(tr);segs.extend(seg);kills.extend(ks)
    (out/'runs.json').write_text(json.dumps(summaries,indent=1))
    for n,v in [('trips',trips),('segments',segs),('kills',kills)]:save(out/(n+'.csv'),v)
