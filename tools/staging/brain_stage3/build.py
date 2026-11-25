"""Build the authorized isolated trial only. The production tree is read-only."""
import os,sys,subprocess
from pathlib import Path
root=Path(__file__).resolve().parent
work=Path(sys.argv[2]).resolve()
stage2=root.parent/'brain_stage2'
sys.path.insert(0,str(stage2))
import five_native
extra=(root/'actuator.inc').read_text()
(work/'trip_guard.hpp').write_bytes((root/'trip_guard.hpp').read_bytes())
hooks=five_native.hooks+'''
changes['status'].append(('#include <common/showmsg.hpp>','#include <common/showmsg.hpp>\\n#include "trip_guard.hpp"'))
changes['status'].append(before('status->hp-= hp;', 'trial::hit(target->id,status->hp,status->max_hp,hp,gettick());'))
changes['population_engine/minimal'].extend([
 ('#include <common/showmsg.hpp>','#include <common/showmsg.hpp>\\n#include "trip_guard.hpp"'),
 before('TIMER_FUNC(follow_tick) {',ACTUATOR),
 ('} else if(hunt!=hunts.end() && hunt->second.mode==TeamMode::mob && hunt->second.opener==sd->id && hunt->second.hold_train){',
  '} else if(hunt!=hunts.end() && hunt->second.mode==TeamMode::mob && trial_execute(shell,owner,hunt->second)){ /* bounded action */ } else if(hunt!=hunts.end() && hunt->second.mode==TeamMode::mob && !hunt->second.retreat && hunt->second.opener==sd->id && hunt->second.hold_train){')])
'''.replace('ACTUATOR',repr(extra))
five_native.hooks=hooks
instrument=five_native.instrument
def observe(code):
    return instrument(code).replace('auto* ice=m->sc.getSCE', '''if(m->mob_id==1213 && distance_bl(m,own)<=12)trial::stop("high_orc",own->id,tick);
    auto* ice=m->sc.getSCE''')
five_native.instrument=observe
os.environ['BRAIN_FIVE']='1'
import runpy
runpy.run_path(str(stage2/'build.py'),run_name='__main__')
