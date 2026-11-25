"""Add a read-only counterfactual at the native decision immediately before the round override."""
from pathlib import Path
import runpy
import sys

parent=Path(__file__).resolve().parents[1]
# Register after rounds hooks, by injecting at the entry to the downstream delivery builder.
# The compiled policy and its normal source stay identical.
import types
real_run=runpy.run_path
def run(path,*args,**kwargs):
    if Path(path)==parent.parent/'brain_delivery/build.py':
        import five_native
        key='const auto previous=h.round;'
        line=r'''const bool native_depart=best && !reason && !h.release_pack;
    const int native_best=best?best->id:0;
    const std::string native_reason=reason?reason:"ok";
    '''
        end='if(previous!=h.round)'
        extra=r'''ShowInfo("B_GATE %lld %d %d %d %d %d %d %zu %d %d %d %d %s\n",(long long)now,int(previous),int(h.round),native_depart,native_best,best?best->id:0,camp_incoming,h.outstanding.size(),hp,ready,reserve,camp_gap,native_reason.c_str());
    '''
        for old,new in [(key,line+key),(end,extra+end)]:
            five_native.hooks+='\nchanges["population_engine/minimal"].append('+repr((old,new))+')\n'
    return real_run(path,*args,**kwargs)
runpy.run_path=run
run(str(parent/'build.py'),run_name='__main__')
