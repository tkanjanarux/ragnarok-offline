"""Summarize held-out predictions, including bounds for incomplete episodes."""
from collections import Counter,defaultdict
from pathlib import Path
import json,statistics,sys
from assess import check

def summarize(dirs):
    cases=Counter(); buckets=defaultdict(Counter);times=defaultdict(list)
    counts=Counter(); proofs={}; misses={}; by_run={}; choices=Counter()
    for d in dirs:
        r=check(next(d.glob('*.log.gz')),d/'decisions.jsonl')
        (d/'check.json').write_text(json.dumps(r,indent=2)+'\n')
        cases.update(r['cases']);choices.update(r['choices'])
        for key,v in r['proof'].items():proofs.setdefault(key,[d.name,v])
        for m in r['misses']:misses[d.name,m['t'],m['actor']]=m
        for key in ('frames','safe','team'):counts[key]+=r[key]
        one=Counter()
        for completed,items in ((True,r['episodes']),(False,r['censored'])):
            for ep in items:
                if ep.get('end')=='recovered':state='recovered_late' if ep['pred'] is not None and ep['actual']>ep['pred'] else 'recovered'
                elif ep['pred'] is None:state='abstain'
                elif completed:state='hit' if ep['actual']<=ep['pred'] else 'late'
                elif ep['end']=='death' or ep['actual']>ep['pred']:state='known_failure'
                else:state='unknown'
                for group in ('all',ep['bucket']):
                    buckets[group][state]+=1
                    if completed:times[group].append((ep['pred'],ep['actual']))
                one[state]+=1
        by_run[d.name]=dict(one,safe=r['safe'],n_team=r['team'])
    return dict(counts=counts,buckets=buckets,medians={k:[statistics.median(x for x,y in v if x is not None),statistics.median(y for x,y in v)] for k,v in times.items()},cases=cases,proof=proofs,misses=[dict(run=k[0],**m) for k,m in misses.items()],by_run=by_run,choices=choices)
if __name__=='__main__':print(json.dumps(summarize(list(map(Path,sys.argv[1:]))),indent=2))
