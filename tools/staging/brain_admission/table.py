"""Group outcomes on the fixed clock, retaining stopped and unproductive windows."""
from collections import Counter
import json,sys
from pathlib import Path

def groups(root):
    data=json.loads((root/'farm.json').read_text());out={}
    for mode in ('0','1'):
        for role in ('knight','priest','all'):
            a=Counter();mat=[]
            for name,r in data.items():
                if name.split('-')[1]!=mode or (role!='all' and not name.endswith(role)):continue
                mat.append(r)
                a.update({k:r[k] for k in ('seconds','base','job','shadow_yes','wait_candidate_frames')})
                e=r['events'];a['runs']+=1;a['trips']+=len(e.get('TRIP',[]))
                a['repeated_runs']+=len(e.get('TRIP',[]))>=2
                a['stop_runs']+=len(e.get('STOP',[]))
                a['unsafe']+=len(r['critical_after_grant'])
                a['foreign_order']+=len(r['out_of_trip'])
                a['owner_deaths']+=r['deaths'].get('2000001',0)
                a['companion_deaths']+=sum(r['deaths'].values())-r['deaths'].get('2000001',0)
                a['sp']+=sum(r['sp'].values());a.update(r['supplies']);a.update(r['recovery'])
                a['pulls']+=len(e.get('PULL',[]));a['targets']+=len(r['targets'])
                a['orders']+=sum(len(v['orders']) for v in r['targets'].values())
                for score in ('swing','damage','aggro','camp','cancel','provoke'):
                    a[score]+=sum(bool(v.get(score)) for v in r['targets'].values())
                for key,value in r['camp_support'].items():
                    a['heal' if key.startswith('28/') else 'kyrie']+=value
                a['incomplete']+=not all(h>=.7*m for h,m in r['final_hp'].values())
                if e.get('APPROVAL'):
                    assert [x[0] for x in e['TRIP']]==[x[0] for x in e['APPROVAL']]
                    for trip,permit in zip(e['TRIP'],e['APPROVAL']):
                        assert trip[-1]==permit[-1] and 0<=trip[0]-permit[1]<=1200
            a['rate']=round(a['base']*600/a['seconds'])
            out[f'{mode}/{role}']=a
    return out
if __name__=='__main__': print(json.dumps(groups(Path(sys.argv[1])),indent=2))
