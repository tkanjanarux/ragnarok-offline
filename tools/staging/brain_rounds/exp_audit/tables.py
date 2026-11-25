"""Produce lookups by matched triplet and arm. Rates use the original wall-time denominator."""
import csv
import itertools
import json
import sys
from collections import Counter,defaultdict
from pathlib import Path
from statistics import median
from analyze import save
root=Path(sys.argv[1]);old=Path(sys.argv[2])
runs=json.loads((root/'runs.json').read_text())
def read(p):return list(csv.DictReader(p.open()))
farm={f"96-{x['field']}-{x['role']}-{x['rep']}-{x['arm']}":x for x in read(old/'farm.csv')}
ks=read(root/'kills.csv');tr=read(root/'trips.csv');fields=read(root/'fields.csv')
arms=['native','delivery','rounds'];keys=sorted(set((r['field'],r['role'],r['rep']) for r in runs))
lookup={r['run']:r for r in runs}
prices={}
for x in ks:
    k=int(x['kind']);p=int(x['exp'])
    assert k not in prices or prices[k]==p
    prices[k]=p
summary=[]
for r in runs:
    name=r['run'];f=farm[name];kills=[x for x in ks if x['run']==name and int(x['exp'])]
    legs=[x for x in tr if x['run']==name];fs=[x for x in fields if x['run']==name]
    end_value=sum(prices.get(kind,0) for _,kind,_ in r['endpack'])
    def total(rows,k):return sum(float(x[k]) for x in rows)
    dist=total(legs,'walk_cells');moving=total(legs,'moving_s')
    summary.append(dict(run=name,field=r['field'],puller=r['role'],rep=r['rep'],arm=r['arm'],exp=r['credited'],
        credited_kills=len(kills),exp_per_paid_kill=round(r['credited']/len(kills),1),
        sampled_departures=r['trips'],initial_camp_exp=sum(int(x['exp']) for x in legs if x['actual_departure']=='False'),
        end_pack=len(r['endpack']),end_value_if_killed=end_value,walk_cells=dist,moving_s=moving,
        speed_when_moving=round(dist/moving,2) if moving else None,
        pack_exit_alive=sum(int(x['pack_exits_alive']) for x in legs),sg_fields=len(fs),sg_kills=sum(x['skill']=='89' for x in kills),
        sg_low=sum(x['level']=='1' for x in fs),sg_high=sum(x['level']=='10' for x in fs),sg_hits=total(fs,'hits'),sg_damage=total(fs,'damage'),
        observed_camp_DS=len(r['camp_open_ds']),later_add_SP_lower_bound=r['later_add_sp_matched'],
        arrows=f['arrows'],sp=f['sp'],white=f['white'],blue=f['blue'],gems=f['gems'],death=f['deaths'],**r['phases']))
save(root/'run-table.csv',summary)
pairs=[];bygroup=defaultdict(list)
for key in keys:
    a=[lookup['-'.join(('96',*key,arm))] for arm in arms];v=[r['credited'] for r in a]
    pairs.append(dict(map=key[0],puller=key[1],rep=key[2],native=v[0],v10=v[1],rounds=v[2],rounds_minus_native=v[2]-v[0],rounds_minus_v10=v[2]-v[1],
        same_initial_gid_position=len(set(r['pos_digest'] for r in a))==1,same_initial_census=all(r['initial_census']==a[0]['initial_census'] for r in a),
        same_initial_within96=all(r['initial_within96']==a[0]['initial_within96'] for r in a)))
    bygroup[key[:2]].append(v)
save(root/'pairs.csv',pairs)
stats={}
for i,arm in enumerate(arms[:2]):
    groups=[[(sum(values[j][2] for j in perm),sum(values[j][i] for j in perm)) for perm in itertools.product(range(2),repeat=2)] for values in bygroup.values()]
    ratios=sorted(100*(sum(s[0] for s in x)/sum(s[1] for s in x)-1) for x in itertools.product(*groups))
    stats[arm]={'empirical_2.5_97.5':[ratios[6],ratios[-7]]}
(root/'sensitivity.json').write_text(json.dumps(stats,indent=2))
