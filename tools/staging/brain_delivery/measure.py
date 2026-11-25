"""Join real field lifetime, footprint and damage to the four marked mobs."""
import gzip
import json
import re
import sys
from collections import defaultdict
from pathlib import Path


def distance(p,q):
    return max(abs(p[0]-q[0]),abs(p[1]-q[1]))


def measure(path):
    wizard, owner, support = 95000002, 2000001, 95000004
    puller = 95000000 if 'priest' in path.name else 95000001
    rear = {wizard,owner,support,95000003}
    mobs,actors,groups,probes,pack,aid = {},{},{},set(),set(),{}
    footprints=defaultdict(list)
    strays=set()
    evidence={'crossings':{},'near_before_hit':{},'damage_events':[],'windows':[], 'fields':[], 'fault':[], 'stops':[], 'docks':[]}
    tagged=set()
    damage=set()
    seen_in_cell=set()
    owners=set()
    unreachable=defaultdict(int)
    all_heals={}
    no_other_healer=defaultdict(int)
    sp_spent=defaultdict(int)
    prev_pull=None
    route=None
    routes=[]
    dock=None
    entry_times={}
    exposure=defaultdict(int)
    near_last=set()
    minimum={}
    actual_aggro=[]
    backline_hits=[]
    dt=0
    previous=None
    age=0
    for line in gzip.open(path,'rt',errors='replace'):
        m=re.search(r'\bB_([A-Z]+) (.*)',line)
        if not m:continue
        kind,raw=m.groups()
        if kind in ('FAULT','STOP','REGROUP'):
            evidence['stops' if kind!='FAULT' else 'fault'].append(raw.strip())
            continue
        if kind not in {'INVALID','PROBE','STRAY','KILL','AGGRO','FIELD','DOCK','WINDOW','FRAME','M','PACK','A','AID','CELL','DONE','HIT','END','DEATH','CANCEL'}:continue
        if kind=='PROBE' and not raw.strip().isdigit():
            evidence.setdefault('emergency_probe',[]).append(raw.strip())
            continue
        v=list(map(int,raw.split()))
        t=v[0]
        if kind=='STRAY':strays.add(t)
        elif kind=='AGGRO' and v[1] in strays:evidence.setdefault('stray_aggro',[]).append(v)
        elif kind=='KILL' and v[1] in strays:evidence.setdefault('stray_killed',[]).append(v)
        elif kind=='HIT' and v[1] in strays and v[2] in rear and v[4]>0:evidence.setdefault('stray_damage',[]).append(v)
        elif kind=='PROBE':probes.add(t)
        elif kind=='FRAME':
            dt=min(t-previous,1000) if previous else 0
            for k,reaches in aid.items():
                if not reaches:unreachable[k]+=dt
            for mid,reaches in all_heals.items():
                if not any(reaches):no_other_healer[mid]+=dt
            for mid in near_last:exposure[mid]+=dt
            near_last=set()
            previous=t;aid={};all_heals={};pack=set();age=v[-1]
        elif kind=='PACK':pack.add(v[1])
        elif kind=='AGGRO' and v[1] in probes:actual_aggro.append(v)
        elif kind=='HIT' and v[1] in probes and v[2] in rear and v[4]>0:backline_hits.append(v)
        elif kind=='AID':
            if v[1]==support:aid[v[2]]=v[3]
            if v[1]!=v[2]:all_heals.setdefault(v[2],[]).append(v[3] and v[4] and v[5])
        elif kind=='HIT' and 95000000<=v[2]<=95000004 and v[5]>0:
            sp_spent[v[2]]+=v[5]
        elif kind=='DOCK':
            dock=tuple(v[3:5]);evidence['docks'].append(v)
        elif kind=='INVALID':
            evidence.setdefault('invalid',[]).append(v);dock=None
        elif kind=='WINDOW':evidence['windows'].append(v)
        elif kind=='M' and v[1] in probes:mobs[v[1]]=(tuple(v[3:5]),v[5])
        elif kind=='A':
            actors[v[1]]=tuple(v[4:6])
            if v[1]==owner:owners.add(actors[owner])
        elif kind=='CELL':footprints[v[1]].append(tuple(v[2:5]))
        elif kind=='FIELD' and v[2:4]==[wizard,89]:
            groups[v[1]]={'t':t,'end':t+v[7],'xy':v[5:7],'hits':0,'victims':set(),'inside':set()}
        elif kind=='END' and v[1] in groups:groups[v[1]]['end']=min(t,groups[v[1]]['end'])
        elif kind=='DONE':
            pos=actors.get(puller)
            returning=age and pack and dock and pos
            if not returning:route=None
            elif route is None:
                route={'start':t,'from':pos,'dock':dock,'direct_cells':distance(pos,dock),
                       'sampled_cells':0,'stationary_ms':0,'observed_ms':0,'closest':distance(pos,dock),'arrived':False}
                routes.append(route)
            elif prev_pull is not None and not route['arrived']:
                step=distance(pos,prev_pull)
                route['sampled_cells']+=step
                route['observed_ms']+=dt
                if not step:route['stationary_ms']+=dt
                route['closest']=min(route['closest'],distance(pos,dock))
            if returning and distance(pos,dock)<=1:route['arrived']=True
            prev_pull=pos
            for mid,(pos,target) in mobs.items():
                if mid not in pack:continue
                if target==puller:tagged.add(mid)
                for who in rear:
                    if who in actors:
                        gap=distance(pos,actors[who])
                        minimum[who]=min(gap,minimum.get(who,gap))
                    if who in actors and distance(pos,actors[who])<=2:
                        entry=[t,mid,target,who,*pos,*actors[who],age]
                        if target==puller:
                            evidence['crossings'].setdefault(str(mid),entry)
                            near_last.add(mid)
                        if mid not in damage:evidence['near_before_hit'].setdefault(str(mid),entry)
                for gid,g in groups.items():
                    if g['t']<=t<g['end'] and any(distance(pos,(x,y))<=r for x,y,r in footprints[gid]):
                        g['inside'].add(mid);seen_in_cell.add(mid);entry_times.setdefault((gid,mid),t)
        elif kind=='HIT' and v[1]==wizard and v[2] in probes and v[3]==89 and v[4]>0:
            damage.add(v[2]);evidence['damage_events'].append(v)
            live=[g for g in groups.values() if g['t']<=t<g['end']]
            if len(live)==1:
                live[0]['hits']+=1;live[0]['victims'].add(v[2])
        elif kind=='DEATH':evidence.setdefault('deaths',[]).append(v)
        elif kind=='CANCEL' and v[1]==wizard:evidence.setdefault('cancel',[]).append(v)
    for gid,g in groups.items():
        evidence['fields'].append(dict(g,gid=gid,victims=sorted(g['victims']),inside=sorted(g['inside'])))
    evidence.update(exposure_ms=dict(exposure),min_gap=minimum,backline_damage=backline_hits,aggro=actual_aggro,routes=routes,first_inside_ms={str(gid):{str(mid):t-groups[gid]['t'] for (g,mid),t in entry_times.items() if g==gid} for gid in groups},probes=sorted(probes),chased=sorted(tagged),hit=sorted(damage),seen_in_field=sorted(seen_in_cell),owner_cells=sorted(owners),unreachable_ms=dict(unreachable),no_external_healer_ms=dict(no_other_healer),sp_debits=dict(sp_spent))
    return evidence


if __name__=='__main__':
    print(json.dumps({p.parent.name:measure(p) for p in sorted(Path(sys.argv[1]).glob('*/*.gz'))},indent=2))
