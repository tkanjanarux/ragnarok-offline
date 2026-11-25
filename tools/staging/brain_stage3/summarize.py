"""Tabulate native outcomes across matched fixed-clock trials without dropping stopped runs."""
from collections import Counter
import json
import math
from pathlib import Path
import sys

def summarize(runs):
    sums=Counter()
    waits=[]
    for row in runs:
        sums.update({k:row[k] for k in ('wall','base','job','gross_owner_base_before_stop','gross_owner_base_after_stop',
                    'issuer_outbound','step_confirmed','short_cycles','heal_within','heal_unresolved_over_bound')})
        sums['runs']+=1
        sums['stop']+=bool(row['stop'])
        sums['owner']+=row['native_deaths'].get('2000001',0)
        sums['others']+=sum(n for k,n in row['native_deaths'].items() if k!='2000001')
        sums['sp_all']+=sum(row['sp'].values())
        sums['sp_camp']+=row['sp'].get('95000004',0)
        sums['below70_seconds']+=row['observed_seconds'].get('low_hp',0)
        sums['dead_seconds']+=row['observed_seconds'].get('dead',0)
        sums['unrecovered_end']+=any(hp<.70*mx for hp,mx in row['final_hp'].values())
        sums['fallback_seconds']+=max(0,row['wall']-row['seconds_before_stop']) if row['stop'] else 0
        sums['critical_after_authorization']+=len(row['critical_after_authorization'])
        sums.update(row['used'])
        sums.update(row['applied'])
        for key,n in row['camp_deliveries'].items():
            sums['heal_camp' if key.startswith('28/') else 'kyrie_camp']+=n
        waits.extend(row['heal_actual_s'])
    sums['base_rate']=round(600*sums['base']/sums['wall'])
    sums['heal_count']=len(waits)
    sums['heal_p90_s']=sorted(waits)[math.ceil(len(waits)*.9)-1] if waits else None
    return sums

def run(root):
    normal=json.loads((root/'normal.json').read_text())
    abnormal=json.loads((root/'emergency.json').read_text())
    groups={}
    for mode in ('0','1'):
        selected={k:v for k,v in normal.items() if k.split('-')[1]==mode}
        for role in ('knight','priest','all'):
            groups[f'{mode}-{role}']=summarize([v for k,v in selected.items() if role=='all' or k.endswith(role)])
    groups['emergency']=summarize(abnormal.values())
    return groups

if __name__=='__main__':
    print(json.dumps(run(Path(sys.argv[1])),indent=2))
