"""Diagnostic executable only. Record the cast decision and vary only the first low-level SG on three targets."""
from pathlib import Path
import runpy
import sys
here=Path(__file__).resolve().parent
sys.path.insert(0,str(here.parents[1]/'brain_stage2'))
import five_native

def add(key,new):
    five_native.hooks+='\nchanges["population_engine/minimal"].append('+repr((key,new))+')\n'
key='if(!h.storm_landed && clustered<4){'
add(key,'''const char* probe_case=std::getenv("DELIVERY_CASE");
  const bool probe=probe_case && std::string(probe_case).find("three_sg_")==0;
  if(probe)ShowInfo("B_CLUSTER %lld %d %d %zu %d %d %d %d %d\\n",(long long)gettick(),target->id,clustered,h.pack.size(),h.storm_landed,h.drop_x,h.drop_y,target->x,target->y);
  const bool trial_high=probe && !strcmp(probe_case,"three_sg_high") && clustered>=2;
  if(!h.storm_landed && clustered<4 && !trial_high){''')
runpy.run_path(str(here.parent/'build.py'),run_name='__main__')
