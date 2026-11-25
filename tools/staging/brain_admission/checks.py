"""Positive and negative controls; never open farming on inconclusive traces."""
from pathlib import Path
import gzip,json,re,sys
from collections import defaultdict

def assess(folder):
    events=defaultdict(list); phase=False; injected=False; complete=False
    for line in gzip.open(next(folder.glob('*.gz')),'rt',errors='replace'):
        match=re.search(r'B_(\w+) (.*)',line)
        if not match:continue
        key,data=match.groups()
        if key=='BOUND' and data=='start':phase=True
        if key=='MARK' and data.startswith('end'):complete=True;break
        if not phase:continue
        if key=='PROBE':injected=True
        if key in ('STOP','REGROUP','HALTED','TRIP','DEATH','COVERMOVE','PEEL','REVIVE','CAST','AID','A','AGGRO','FRAME','TAG','PULL'):
            events[key].append([int(v) if v.lstrip('-').isdigit() else v for v in data.split()])
    e=events;probe,role=folder.name.split('-')
    reasons={'manual':'manual','heartbeat':'heartbeat','late':'help_late','critical':'critical_hit','range':'puller_out_of_heal','orc':'high_orc','orc_late':'high_orc'}
    ok=complete
    summary=dict(complete=complete,injected=injected,stops=e['STOP'],moves=e['COVERMOVE'],peels=e['PEEL'],
                 deaths=[a[1] for a in e['DEATH']],raises=[a for a in e['CAST'] if a[2]==54])
    if probe in reasons:
        ok=ok and len(e['STOP'])==1 and e['STOP'][0][1]==reasons[probe]
        stop=e['STOP'][0][0] if e['STOP'] else 0
        ok=ok and bool(e['REGROUP']) and 0<=e['REGROUP'][0][0]-stop<=500 and len(e['HALTED'])==5 and all(a[2:]==[0,0] for a in e['HALTED'])
        ok=ok and not any(a[0]>=stop for k in ('TRIP','TAG','PULL') for a in e[k])
    if probe.startswith('orc'):
        summary['unsafe_raise_blocks']=len([a for a in e['REVIVE'] if not a[-1]])
        summary['peels_confirmed']=sum(a[2]!=95000001 and a[3]==95000001 for a in e['PEEL'])
        ok=ok and not summary['raises'] and summary['unsafe_raise_blocks']>0
    if probe=='cover':
        after=[a for a in e['AID'] if a[1]==95000004 and a[2]==95000002]
        miss=next((a[0] for a in after if not a[3]),None)
        repair=next((a[0] for a in after if miss and a[0]>miss and all(a[3:])),None)
        moves=[a for a in e['COVERMOVE'] if miss and a[0]>=miss-400 and repair and a[0]<repair]
        summary['reach_restored_ms']=repair-miss if repair else None
        ok=ok and injected and not e['STOP'] and bool(moves)
    if probe=='raise':
        died=any(a[1]==2000001 for a in e['DEATH'])
        ok=ok and died and any(a[1]==95000004 and a[4]==2000001 for a in summary['raises']) and all(a[1]==95000004 for a in summary['raises']) and any(a[1]==2000001 and a[6]>0 and a[0]>e['DEATH'][0][0] for a in e['A'])
    summary['pass']=bool(ok)
    return summary

if __name__=='__main__':
    root=Path(sys.argv[1]); results={d.name:assess(d) for d in sorted(root.iterdir())}
    print(json.dumps(results,indent=2))
    sys.exit(0 if len(results)==11 and all(x['pass'] for x in results.values()) and any(x.get('peels_confirmed',0) for x in results.values()) else 1)
