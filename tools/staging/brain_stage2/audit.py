"""Report discrete critical crossings, use of fallback and actual layer cadence."""
from pathlib import Path
import json,statistics,sys
from planner import World,TEAM,readlog

def audit(d):
    decisions={p['t']:p for l in (d/'decisions.jsonl').read_text().splitlines() if 'team' in (p:=json.loads(l))}
    latest=None;low=set();cross=[];scope=None
    for k,row in World().frames(readlog(next(d.glob('*.log.gz')),False)):
        if k=='frame':
            latest=decisions.get(row['t'],latest)
            observed=[(i,a[6]) for i,a in row['a'].items()]
            t=row['t']
        elif k=='HIT' and row[2] in TEAM and row[4]>0:
            observed=[(row[2],max(0,row[6]-row[4]))];t=row[0]
        else:continue
        if not latest:continue
        for i,hp in observed:
            if hp<=latest['floor'][str(i)]:
                if i not in low:cross.append(dict(t=t,actor=i,hp=hp,reason=latest['reason'],safe=latest['safe']))
                low.add(i)
            else:low.discard(i)
    tick=list(decisions)
    return dict(critical_crossings=cross,median_team_interval_ms=statistics.median(b-a for a,b in zip(tick,tick[1:])),span_s=(tick[-1]-tick[0])/1000)
if __name__=='__main__':
    print(json.dumps({p.name:audit(p) for p in map(Path,sys.argv[1:])},indent=2))
