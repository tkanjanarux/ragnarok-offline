"""Produce weighted rates and individual pair deltas from the complete experiment."""
import csv
import json
import sys
from collections import Counter
from pathlib import Path
from statistics import median

root=Path(sys.argv[1])
rows=list(csv.DictReader((root/'farm-runs.csv').open()))
pairs=list(csv.DictReader((root/'farm-pairs.csv').open()))
assert len(rows)==16 and len(pairs)==8
keys='seconds base deaths stops sp gem arrows damage wizard_damage field_hits fields empty unrecovered chasers_near'.split()
def join(rs):
    totals=Counter()
    used=Counter()
    for r in rs:
        for key in keys:totals[key]+=int(r[key])
        for key in ('native_retreat_s','rear_s','wiz_wounded_out_s','pull_wounded_out_s','dead_s'):totals[key]+=float(r[key])
        used.update(json.loads(r['supplies']))
    totals['per10']=round(600*totals['base']/totals['seconds'])
    return dict(totals),dict(used)
stats={}
for field,role in [('07','knight'),('07','priest'),('09','knight'),('09','priest'),('*','*')]:
    key=field+'-'+role
    stats[key]={}
    for arm in ('native','delivery'):
        rs=[r for r in rows if r['arm']==arm and (field=='*' or r['field']==field and r['puller']==role)]
        stats[key][arm],stats[key][arm+'_items']=join(rs)
    a,b=stats[key]['native'],stats[key]['delivery']
    ds=[int(p['delta_per10']) for p in pairs if field=='*' or '-'+key+'-' in p['pair']]
    stats[key].update(percent=round(100*(b['base']/b['seconds']/(a['base']/a['seconds'])-1),2),
                      pair_delta_per10=ds,median_pair_delta_per10=median(ds))
(root/'farm-total.json').write_text(json.dumps(stats,indent=2)+'\n')
