"""Export every attempt (including runs in which a fault did not trigger)."""
import csv
import json
import sys
from pathlib import Path

from measure import measure

root=Path(sys.argv[1])
events={}
rows=[]
for trace in sorted(root.glob('*/*.log.gz')):
    name=trace.parent.name
    v=measure(trace)
    events[name]=v
    result=json.loads(next(line for line in reversed(trace.with_suffix('').with_suffix('.result').read_text().splitlines()) if line.startswith('{')))
    support_loss=v['unreachable_ms']
    tug=95000000 if 'priest' in name else 95000001
    rows.append(dict(run=name,seconds=result['seconds'],base=result['base'],deaths=result['owner_deaths']+result['companion_deaths'],
        pulled=len(v['chased']),sampled_in_field=len(v['seen_in_field']),sg_victims=len(v['hit']),fields=len(v['fields']),
        field_hits=sum(f['hits'] for f in v['fields']),empty_fields=sum(not f['hits'] for f in v['fields']),
        rear_chasing=len(v['crossings']),rear_before_sg=len(v['near_before_hit']),invalidations=len(v.get('invalid',[])),
        fault=' | '.join(v['fault']),critical_stops=sum('critical' in item for item in v['stops']),
        wiz_out_s=round(support_loss.get(95000002,0)/1000,2),pull_out_s=round(support_loss.get(tug,0)/1000,2),
        sp_debits=sum(v['sp_debits'].values()),stock_debits=json.dumps(result['used'],sort_keys=True),
        sampled_return_cells=sum(r['sampled_cells'] for r in v['routes']),
        stationary_return_s=round(sum(r['stationary_ms'] for r in v['routes'])/1000,2)))
(root/'events.json').write_text(json.dumps(events,indent=2)+'\n')
with (root/'attempts.csv').open('w') as out:
    writer=csv.DictWriter(out,fieldnames=rows[0])
    writer.writeheader()
    writer.writerows(rows)
