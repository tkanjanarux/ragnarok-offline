"""Count real events and frame durations, retaining every arm and paired start check."""
import csv
import gzip
import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'brain_delivery'))
from farm_results import field_counts, position_reader

def timeline(d):
    state=0
    totals=Counter()
    active=False
    prev=None
    seen_pack=False
    open_trip=False
    ids={2000001,*range(95000000,95000005)}
    threat=False
    stopped=False
    ground={}
    rear_idle=False
    last_threat=None
    for line in gzip.open(next(d.glob('*.gz')),'rt'):
        m=re.search(r'B_(MARK|ROUND|SECURE|FRAME|PULLSTATE|PACK|DONE|M|STOP|FIELD|END|A) (.*)',line)
        if not m:continue
        key,raw=m.groups()
        if key=='MARK':active=raw.startswith('start');continue
        if key=='STOP':stopped=True;continue
        if key=='ROUND':
            v=list(map(int,raw.split()));state=v[2]
            if active and state==1:
                totals['round_starts']+=1
                totals['starts_carrying']+=bool(v[3])
                if last_threat:totals['start_after_threat_frame']+=1
            continue
        if not active:continue
        if key=='SECURE':totals['secured']+=1;continue
        v=list(map(int,raw.split()))
        if key=='FRAME':pack=False;threat=False;anchor=v[3:5]
        elif key=='FIELD' and v[2:4]==[95000002,89]:ground[v[1]]=v[0]+v[7]
        elif key=='END':ground.pop(v[1],None)
        elif key=='A' and v[1]==95000002:rear_idle=not(v[12] or v[13] or v[16])
        elif key=='PACK':pack=True
        elif key=='PULLSTATE':tag=bool(v[1] and not v[2]);released=v[2]
        elif key=='M' and v[5] in ids and max(abs(v[3]-anchor[0]),abs(v[4]-anchor[1]))<=7:threat=True
        elif key=='DONE':
            # All arms use the same sampled definition. Returning and clearing are combined.
            label='stop' if stopped else 'collect' if tag else 'return_clear' if pack or threat else 'available'
            last_threat=threat
            if prev:
                t,prior,phase,idle=prev;dt=(v[0]-t)/1000
                if prior=='collect' and idle:totals['wiz_wait_s']+=dt
                totals[prior+'_s']+=dt;totals['phase'+str(phase)+'_s']+=dt
            prev=v[0],label,state,rear_idle and not any(end>v[0] for end in ground.values())
            if tag and not open_trip:open_trip=True
            if open_trip and (pack or threat):seen_pack=True
            if open_trip and seen_pack and not(pack or threat):
                totals['frame_completions']+=1;open_trip=seen_pack=False
    return totals

def main(root):
    rows=[];starts={};first_frames={}
    for d in sorted((root/'farm').iterdir()):
        _,field,role,rep,arm=d.name.split('-')
        r=position_reader()(d);f=field_counts(d);t=timeline(d)
        setup=(r['anchor'],r['gear'],{k:[*v[:3],*v[-2:]] for k,v in r['build'].items()},f['start_stock'])
        starts.setdefault((field,role,rep),[]).append((arm,setup))
        first_frames.setdefault((field,role,rep),{})[arm]=r['first']
        rows.append(dict(field=field,role=role,rep=rep,arm=arm,seconds=r['seconds'],exp=r['base'],damage=sum(r['damage'].values()),
            wizard_damage=r['damage'][95000002],sp=sum(r['sp'].values()),deaths=sum(r['deaths'].values()),stops=len(r['stops']),
            white=r['used'].get(11623,0),blue=r['used'].get(11624,0),gems=r['used'].get(717,0),
            arrows=sum(r['used'].get(i,0) for i in (1750,1754)),fields=f['fields'],hits=f['field_hits'],
            camp_heals=r['healing'][95000004]['heal'],puller_wounded_out_s=round(r['metrics']['pull_unreachable_need_s'],2),
            native_retreat_s=f['retreat_s'],**{k:round(t[k],2) for k in ('collect_s','return_clear_s','available_s','stop_s','wiz_wait_s','frame_completions')},
            **{k:(round(t[k],2) if arm=='rounds' else '') for k in ('secured','round_starts','starts_carrying','start_after_threat_frame','phase0_s','phase1_s','phase2_s','phase3_s')}))
    with (root/'farm.csv').open('w') as o:
        w=csv.DictWriter(o,fieldnames=rows[0]);w.writeheader();w.writerows(rows)
    pairs={str(k):dict(arms=[a for a,_ in v],same_start=all(s==v[0][1] for _,s in v)) for k,v in starts.items()}
    for k,by_arm in first_frames.items():
        pair=pairs[str(k)]
        pair['first_frame_vitals']=by_arm
        pair['same_first_frame_hp_sp']=all(s==by_arm['native'] for s in by_arm.values())
    (root/'pairs.json').write_text(json.dumps(pairs,indent=2)+'\n')
if __name__=='__main__':main(Path(sys.argv[1]))
