"""Calculate coverage with competing recovery and summarize paired pull exposure."""
from collections import Counter
import json,sys
from pathlib import Path
from summary import summarize
from pull_compare import compare

def coverage(b):
    # Resolved at/before deadline never enters the Heal denominator. A missing
    # prediction cannot be counted as a successful numerical forecast.
    c=Counter(b);n=sum(c.values())-c['recovered'];issued=n-c['abstain']
    def bounds(denom):
        if not denom:return None
        return [round(100*h/denom,2) for h in (c['hit'],c['hit']+c['unknown'])]
    return dict(issued=issued,all_need=n,issued_coverage=bounds(issued),all_need_coverage=bounds(n),outcomes=b)

def main(root):
    totals=Counter();all_misses=[];out={}
    for name,pattern in [('normal','check-field*'),('deficit','check-need-*'),('pressure','check-pressure*-*'),('late','check-late-*'),('approach','check-approach-*')]:
        dirs=sorted(p for p in root.glob(pattern) if p.is_dir())
        if not dirs:continue
        s=summarize(dirs)
        (root/(name+'-final.json')).write_text(json.dumps(s,indent=2)+'\n')
        totals.update(s['buckets']['all']);all_misses+=s['misses']
        out[name]=dict(coverage=coverage(s['buckets']['all']),cases=s['cases'],counts=s['counts'],misses=s['misses'])
        if name=='normal':
            paired={p.name:compare(p) for p in dirs}
            (root/'paired-final.json').write_text(json.dumps(paired,indent=2)+'\n')
            for role in ('knight','priest','all'):
                c=Counter()
                for run,res in paired.items():
                    if role=='all' or run.endswith(role):c.update(res['counters'])
                out[name][role]=dict(c,**{k:round(100*c[k+'_ms']/c['ms'],2) for k in ('permit','recommended','native_intent','native_action')})
    out['combined']=coverage(dict(totals));out['misses']=all_misses
    print(json.dumps(out,indent=2))
if __name__=='__main__':main(Path(sys.argv[1]))
