"""One prediction per injured actor per episode. Outcomes use native Heal HP credits."""
import argparse
from collections import Counter,defaultdict
import gzip,json,math
from pathlib import Path
from planner import World,readlog,K,P,W,TEAM,pos,dist,partition,needs_heal

def episodes(path,decisions=None):
    active={};finished=[];other=[];world=World();now=0;health={}
    def end(i,t,reason):
        if i in active:
            ep=active.pop(i)
            ep.update(actual=(t-ep['t'])/1000)
            if reason=='heal':finished.append(ep)
            else:
                ep['end']=reason
                other.append(ep)
    for k,f in world.frames(readlog(path,False)):
        if k!='frame':
            now=max(now,f[0])
            if k=='effect':end(f[1],f[0],'heal')
            if k=='DEATH':end(f[1],f[0],'death')
            if k=='HIT' and f[2] in health:
                health[f[2]][0]=max(0,f[6]-f[4])
            if k=='restore' and f[1] in health:
                h=health[f[1]]
                h[0]=min(h[1],h[0]+f[2])
                if h[0]*100>=h[1]*70:end(f[1],f[0],'recovered')
            continue
        now=f['t']
        for i,a in f['a'].items():
            health[i]=[a[6],a[7]]
            if not needs_heal(a):
                end(i,now,'recovered' if a[6] else 'death')
            elif i not in active and (decisions is None or now in decisions):
                base,bucket=partition(f,i)
                pred=decisions[now]['eta'][str(i)] if decisions is not None else None
                active[i]=dict(actor=i,t=now,base=base,bucket=bucket,pred=pred)
    for i in list(active):end(i,now,'end')
    return finished,other

def fit(paths):
    bins=defaultdict(list)
    for path in paths:
        done,other=episodes(path)
        for e in done+other:bins[e['bucket']].append(e)
    def bound(rows):
        # A recovery before the deadline removes demand, never a successful Heal.
        # Death and any still-open demand past deadline are failures.
        for margin in [n*.5 for n in range(1,121)]:
            ok=n=0
            for e in rows:
                end=e.get('end','heal');within=e['actual']<=e['base']+margin
                if end in ('recovered','end') and within:continue
                n+=1;ok+=int(end=='heal' and within)
            if n and ok/n>=.95:return margin+.5
        return 60
    return {k:bound(v) for k,v in bins.items()},{k:dict(Counter(e.get('end','heal') for e in v)) for k,v in bins.items()}

def check(path,plans):
    frames=[json.loads(l) for l in plans.read_text().splitlines()]
    decisions={r['t']:r for r in frames if 'team' in r}
    eps,cens=episodes(path,decisions)
    world=World();cases=Counter();safe=[];misses=[];prev_buffs={};last_target={};ts=[];scope=None
    roster=TEAM
    def danger(t,i,hp):
        for start,deadlines,floors in safe:
            if i in deadlines and t<=deadlines[i] and hp<=floors[i]:
                misses.append(dict(t=t,actor=i,hp=hp,forecast=start,floor=floors[i]))
                del deadlines[i]
    proof={};shield={}
    for k,f in world.frames(readlog(path,False)):
        if k=='BREAK' and f[1] in roster:
            cases['native_shield_break']+=1
            if shield.get(str(f[1]),0)>f[0]+500:
                cases['break_before_forecast']+=1
                proof.setdefault('unexpected_break',dict(t=f[0],actor=f[1],forecast=shield[str(f[1])],hp_left=f[2],hits_left=f[3]))
            if (f[1],39) in prev_buffs and prev_buffs[f[1],39][2]>f[0]+1000:
                cases['native_break_before_expiry']+=1
                proof.setdefault('shield',dict(t=f[0],actor=f[1],hp_budget=f[2],hits_left=f[3],nominal_expiry=prev_buffs[f[1],39][2]))
        if k=='INTERRUPT' and f[1:3]==[W,89]:
            cases['native_interrupt_sg']+=1
            proof.setdefault('sg',dict(t=f[0],actor=f[1]))
        if k=='effect':
            for _,limits,_ in safe:limits.pop(f[1],None)
        if k=='HIT' and f[2] in roster and f[4]>0:danger(f[0],f[2],max(0,f[6]-f[4]))
        if k=='DEATH' and f[1] in roster:danger(f[0],f[1],0)
        if k=='CANCEL' and f[1:3]==[W,89]:cases['sg_interrupted']+=1
        if k=='KILL':last_target.pop(f[1],None)
        if k=='AGGRO' and f[2] in roster:last_target[f[1]]=f[2]
        if k=='AGGRO' and f[3] in roster:
            if last_target.get(f[1],f[3])!=f[3]:cases['retarget']+=1
            last_target[f[1]]=f[3]
        if k!='frame':continue
        t=f['t'];ts.append(t);roster=tuple(f['a'])
        for i in roster:danger(t,i,f['a'][i][6])
        safe=[s for s in safe if any(end>=t for end in s[1].values())]
        if any(m[5] in roster and dist(m[3:5],f['anchor'])<=5 for m in f['m'].values()):cases['camp_attack_frames']+=1
        if not f['cover'][W][0]:cases['priest_out_of_range_frames']+=1
        for (i,b),vals in prev_buffs.items():
            if b==39 and (i,b) not in f['buff'] and vals[2]>t+1000 and f['a'][i][6]>0:cases['kyrie_early_loss']+=1
        prev_buffs=f['buff']
        dec=decisions.get(t)
        if dec:
            shield=dec.get('shield_until',{})
            if dec['peer_conflict']:
                cases['peer_on_route_frames']+=1
                assert not dec['safe']
                proof.setdefault('peer',dict(t=t,peer=f['peer'],puller=pos(f['a'][f['pull']]),move=f['a'][f['pull']][10:12],chosen=dec['team']))
            if dec['safe']:
                safe.append((t,{i:(float('inf') if f['a'][i][6]<.70*f['a'][i][7] or (not f['cover'][i][0] and any(m[5]==i for m in f['m'].values())) else t+1000*max(8,dec.get('help_if_hit',dec['eta'])[str(i)] or 120)) for i in roster},{i:dec['floor'][str(i)] for i in roster}))
    assert len(ts)==len(frames) and ts==[p['t'] for p in frames], 'incomplete live stream'
    return dict(episodes=eps,censored=cens,proof=proof,cases=cases,frames=len(ts),team=len(decisions),safe=sum(r['safe'] for r in decisions.values()),misses=misses,choices=dict(Counter('/'.join(r['team']) for r in decisions.values())))
if __name__=='__main__':
    import sys
    if sys.argv[1]=='fit':
        model,counts=fit(list(map(Path,sys.argv[2:])))
        print(json.dumps(model));print(counts,file=sys.stderr)
    else:
        print(json.dumps(check(Path(sys.argv[2]),Path(sys.argv[3])),indent=2))
