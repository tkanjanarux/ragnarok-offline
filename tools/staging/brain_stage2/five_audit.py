"""Audit native party membership, SP debits and actual skills during the benchmark window."""
from collections import Counter
from pathlib import Path
import gzip,json,sys
from planner import CAMP,OWNER,P,K,W,H,TEAM,RX,dist
from prep_audit import audit

def measure(directory, five):
    roster=(*TEAM,CAMP) if five else TEAM
    profiles={actor:i for i,actor in enumerate(roster)}
    # actor order in TEAM is owner, original Priest, Knight, Wizard, Hunter.
    party={};positions={};action=Counter();away_action=Counter();sp=Counter()
    deaths=Counter(); away_samples=[];joins=Counter();evidence=[]
    active=False; tick=0;anchor=None;party_id=None;frames=0
    max_orcs=0
    with gzip.open(next(directory.glob('*.gz')),'rt',errors='replace') as stream:
        for line in stream:
            match=RX.search(line)
            if not match:continue
            k,raw=match.groups()
            if k=='BOUND' and raw.strip()=='start':active=True;continue
            if k=='MARK' and raw.startswith('end'):break
            if not active:continue
            try:v=list(map(int,raw.split()))
            except ValueError:continue
            if k=='FRAME':
                tick=v[0]
                anchor=v[3:5];pull=P if v[7] else K;shields=set()
                party={};positions={};orcs=0
            elif k=='BUFF' and v[2]==39 and v[3]>0:shields.add(v[1])
            elif k=='BREAK':shields.discard(v[1])
            elif k=='M':orcs+=v[2]==1213
            elif k=='A':
                assert profiles[v[1]]==v[2],(directory,v)
                positions[v[1]]=v[4:6]
            elif k=='PARTY':
                assert v[2]==v[3] and v[2]>0,(directory,v)
                party_id=v[2];party[v[1]]=v[4]
            elif k=='DONE':
                max_orcs=max(max_orcs,orcs)
                if set(party)==set(roster):
                    assert party[P]==8 and (not five or party[CAMP]==8)
                    frames+=1;joins.update(party.keys())
                    if dist(positions[pull],anchor)>9 and five:
                        away_samples.append(dist(positions[CAMP],anchor))
            elif k=='HIT' and v[2] in roster and v[5]>0:sp[v[2]]+=v[5]
            elif k=='DEATH' and v[1] in roster:deaths[v[1]]+=1
            elif k=='DELIVER' and anchor and v[2] in roster:
                t,src,target,skill,hp,shield=v
                new_shield=skill==73 and shield>0 and target not in shields
                if skill==73 and shield>0:shields.add(target)
                if src!=CAMP or not (skill==28 and hp>0 or new_shield):continue
                key=f'{skill}/{target}';action[key]+=1
                if anchor and pull in positions and t-tick<=1000 and dist(positions[pull],anchor)>9:
                    away_action[key]+=1
                    if away_action[key]==1:
                        evidence.append(dict(t=t,target=target,skill=skill,actual_hp=hp,shield_points=shield,
                                             puller_gap=dist(positions[pull],anchor),camp_priest_gap=dist(positions[CAMP],anchor)))
    assert frames and len(joins)==len(roster)
    result=audit(directory)
    result.update(frames=frames,party_id=party_id,profiles=profiles,joined_frames=joins,sp_debit=sp,
                  native_deaths=deaths,delivered=action,while_away=away_action,examples=evidence,
                  away_frames=len(away_samples),in_camp_while_away=sum(g<=9 for g in away_samples),max_orcs=max_orcs)
    return result

if __name__=='__main__':
    root=Path(sys.argv[1]);five=sys.argv[2]=='5'
    print(json.dumps({d.name:measure(d,five) for d in sorted(root.glob('check-*/'))},indent=2))
