"""Gate the limited normal trial on observed stops with this fixture."""
import gzip,json,re,sys
from pathlib import Path

def verify(folder,expected):
    data=gzip.open(next(folder.glob('*.log.gz')),'rt').read()
    stops=re.findall(r'B_STOP (\d+) (\w+) (\d+)',data)
    assert len(stops)==1 and stops[0][1]==expected,(folder,stops)
    tick=int(stops[0][0]); halt=re.findall(r'B_HALTED (\d+) (\d+) (\d+) (\d+)',data)
    assert {int(i) for _,i,_,_ in halt}==set(range(95000000,95000005))
    assert all(w=='0' and a=='0' for _,_,w,a in halt)
    regroup=int(re.search(r'B_REGROUP (\d+)',data)[1])
    assert 0<=regroup-tick<=500
    actions=[int(t) for t in re.findall(r'B_APPLY (\d+)',data)]
    assert actions and max(actions)<tick
    assert all(int(t)<tick for t in re.findall(r'B_PULL (\d+)',data))
    assert 'B_BOUND end' in data and 'B_BOUND start' in data
    return dict(reason=expected,actor=int(stops[0][2]),applied_before=len(actions),regroup_ms=regroup-tick,
                halted=len(halt),applied_after=0)
if __name__=='__main__':
    root=Path(sys.argv[1])
    print(json.dumps({n:verify(root/n,r) for n,r in [('critical','critical_hit'),('late','help_late'),('range','puller_out_of_heal'),('manual','manual'),('heartbeat','heartbeat')]},indent=2))
