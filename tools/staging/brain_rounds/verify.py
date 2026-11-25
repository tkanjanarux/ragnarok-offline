"""Assert the evidence paths from the constrained trial, keeping emergency outcome separate."""
import json
import sys
from pathlib import Path

data=json.loads((Path(sys.argv[1])/'probe-events.json').read_text())
two=data['challenges/probe-repeat']
assert len(two['initial_kills'])==4 and all(two['initial_kills'])
assert two['first_pull_second'][0]>max(two['initial_kills'])
for scenario in ('camp_add','overlap'):
    case=data['challenges/probe-'+scenario]
    hunter,wizard=case['first_hunter'],case['first_wizard']
    assert hunter[3]==46 and hunter[4]>0 and wizard[4]>0 and hunter[0]<wizard[0]
    assert wizard[3]!=89 and case['add_killed']
    assert case['actual_sg_damage'] and all(case['initial_kills'])
# At least one field became active while the single target was still alive.
assert any(r['first_wizard'][0]<f[0]<r['add_killed']
           for r in (data['challenges/probe-'+s] for s in ('camp_add','overlap')) for f in r['fields'])
case=data['challenges/probe-self_defense']
assert case['first_wizard'] and (not case['first_hunter'] or case['first_wizard'][0]<case['first_hunter'][0])
assert any(e[3]==95000002 and e[0]<=case['first_wizard'][0] for e in case['add_aggro'])
case=data['final/probe-withdraw']
entered=next(e[0] for e in case['rounds'] if e[2]==3)
recovered=next(e[0] for e in case['rounds'] if e[1]==3 and e[2]!=3)
assert entered<min(case['initial_kills'])<=max(case['initial_kills'])<=recovered
assert any(entered<f[0]<recovered for f in case['fields'])
print('Verified sequencing, Hunter-first, active-threat defense, overlapping SG and fighting withdrawal.')
case=data['final/probe-emergency']
print('Independent emergency observation:',case['stops'],case['deaths'])
