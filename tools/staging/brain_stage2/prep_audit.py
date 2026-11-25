"""Paired shadow accounting. All native outcomes and hypothetical costs are separate."""
import gzip
import json
import re
import sys
from collections import Counter
from pathlib import Path

def exposure(rows, episodes):
    times=Counter()
    prev_key=None
    busy_until=0
    for a,b in zip(rows,rows[1:]):
        dt=min(1,(b['t']-a['t'])/1000)
        prep=a.get('prep')
        state='permit' if a['safe'] else 'prepare' if prep else 'wait'
        times[state]+=dt
        key=(prep['actor'],prep['target'],prep['action'],tuple(prep['cell'])) if prep else None
        if key and key!=prev_key and a['t']>=busy_until:
            episodes.append((a['t'],prep))
            times['sim_'+prep['action']]+=1
            times['sim_seconds']+=prep['seconds']
            times['sim_sp']+=prep['sp']
            times['projected_ready']+=int(prep['potential_ready'])
            busy_until=a['t']+1000*prep['seconds']
            prev_key=key
        if key is None:prev_key=None
    return times

def audit(d):
    rows=[v for l in (d/'decisions.jsonl').read_text().splitlines() if 'safe' in (v:=json.loads(l))]
    episodes=[]
    times=exposure(rows,episodes)
    fixture=json.loads(next(d.glob('*.result')).read_text().splitlines()[-1])
    marks={}; supplies={};deaths={}; casts=[]; buffs=[]; positions=[]
    with gzip.open(next(d.glob('*.gz')),'rt',errors='replace') as log:
        boundary=None
        for line in log:
            if m:=re.search(r'B_CAST (\d+) (9500000[04]) 73 \d+ (\d+)',line):
                casts.append(tuple(map(int,m.groups())))
            elif m:=re.search(r'B_BUFF (\d+) (\d+) 39 (\d+) (\d+) (\d+)',line):
                buffs.append(tuple(map(int,m.groups())))
            elif m:=re.search(r'B_A (\d+) 95000001 \d+ \d+ (\d+) (\d+)',line):
                positions.append(tuple(map(int,m.groups())))
            if m:=re.search(r'B_MARK (start|end) ([\d ]+)',line):
                boundary=m[1]; marks[boundary]=list(map(int,m[2].split()))
                supplies[boundary]=Counter(); deaths[boundary]={}
            elif boundary and (m:=re.search(r'B_STOCK (\d+) (-?\d+) (\d+)',line)):
                supplies[boundary][abs(int(m[2]))]+=int(m[3])
            elif boundary and (m:=re.search(r'B_COUNTER (\d+) (\d+)',line)):
                deaths[boundary][m[1]]=int(m[2])
    for tick,plan in episodes:
        deadline=tick+1000*plan['seconds']+500
        if plan['action']=='kyrie':
            confirmed=next((t for cast,caster,patient in casts if caster==plan['actor'] and tick<=cast<=deadline and patient==plan['target']
                            for t,who,hp,hits,exp in buffs if cast<=t<=deadline and who==patient and
                            hp>0 and hits>0 and exp>cast+110000),None)
        else:
            confirmed=next((t for t,x,y in positions if tick<t<=deadline and (x,y)==tuple(plan['cell'])),None)
        if confirmed is not None:
            times['observed_'+plan['action']]+=1
            if any(r['safe'] and confirmed<=r['t']<=confirmed+2500 for r in rows):
                times['observed_then_permit']+=1
    start,end=marks['start'],marks['end']
    assert start[::2]==end[::2], 'level transition needs EXP rollover accounting'
    lost=supplies['start'].copy();lost.subtract(supplies['end'])
    return dict(times=times,seconds=fixture['seconds'],base=end[1]-start[1],job=end[3]-start[3],
                used={k:v for k,v in lost.items() if v},owner_deaths=fixture['owner_deaths'],
                companion_deaths=fixture['companion_deaths'])

if __name__=='__main__':
    print(json.dumps({p.name:audit(p) for p in map(Path,sys.argv[1:])},indent=2))
