"""Assemble only the isolated admission fixture from the pinned observer."""
import os,runpy,sys
from pathlib import Path
root=Path(__file__).resolve().parent
stage2=root.parent/'brain_stage2'
stage3=root.parent/'brain_stage3'
sys.path.insert(0,str(stage2))
import five_native
work=Path(sys.argv[2]);(work/'trip_guard.hpp').write_bytes((stage3/'trip_guard.hpp').read_bytes())
guard=(stage3/'actuator.inc').read_text().split('    if(!pull || !healer)return true;')[0]
guard=guard.replace('return false; // Existing retreat branch handles Heal and regroup.', 'return defensive_peel(shell,owner);')
guard+='    return false; // Native actors exclusively own trip actions.\n}\n'
def inject(key,old,new):
    global hooks
    hooks+='\nchanges['+repr(key)+'].append('+repr((old,new))+')\n'
hooks=five_native.hooks
for key in ('status','population_engine/minimal'):
    inc='#include <common/showmsg.hpp>'
    inject(key,inc,inc+'\n#include "trip_guard.hpp"')
inject('status','status->hp-= hp;', 'trial::hit(target->id,status->hp,status->max_hp,hp,gettick());\nstatus->hp-= hp;')
def ai(old,new):inject('population_engine/minimal',old,new)
key='bool support_party(Shell&'
ai(key,(root/'cover.inc').read_text()+'\nstatic bool camp_cover(Shell&,map_session_data*);\n'+key)
ai('if(pc_isdead(ally) && pc_search_inventory','if(pc_isdead(ally) && resurrection_safe(shell,ally,owner) && pc_search_inventory')
key='if(shell.profile==5 && farming){'
ai(key,key+'\n if(admission_enabled() && !emergency_only && !battle_check_range(sd,map_id2sd(95000002),8))return camp_cover(shell,owner);')
key='if(distance_bl(sd,owner)>3 && sd->ud.walktimer==INVALID_TIMER)'
ai(key,'if(admission_enabled())camp_cover(shell,owner); else '+key)
key='TIMER_FUNC(follow_tick) {'
ai(key,(root/'position.inc').read_text()+guard+'\n'+key)
key='} else if(hunt!=hunts.end() && hunt->second.mode==TeamMode::mob && hunt->second.opener==sd->id && hunt->second.hold_train){'
ai(key,'} else if(hunt!=hunts.end() && hunt->second.mode==TeamMode::mob && trial_execute(shell,owner,hunt->second)){ /* reflex */ '+key)
key='if(reason){\n        h.inbound='
ai(key,(root/'gate.inc').read_text()+'\n'+key)
key='if(h.retreat || !unclaimed(owner,mob)'
ai(key,'if(h.retreat && admission_enabled() && sd->id==95000001 && trial_peel==mob->id && peel_allowed(owner,mob))return true;\n            '+key)
key='return owner && h.mode==TeamMode::mob && !h.retreat'
ai(key,'if(h.retreat && admission_enabled() && src->id==95000001 && trial_peel==mob->id && peel_allowed(owner,mob))return true;\n    '+key)
key='unit_attack(sd,pull->id,0);'
ai(key,'ShowInfo("B_TAG %lld %d %d %d\\n",(long long)gettick(),trial_trip,sd->id,pull->id); '+key)
key='ud->attacktarget_lv = battle_weapon_attack(src,target,tick,0);'
inject('unit',key,key+'\nif(sd)ShowInfo("B_SWING %lld %d %d %d\\n",(long long)tick,src->id,target->id,ud->attacktarget_lv);')
ai('static bool pull_cell(const Hunt& h,int x,int y){','static bool pull_cell(const Hunt& h,int x,int y){ if(distance_xy(x,y,h.x,h.y)>4)return false;')
ai('static bool pull_step(const Hunt& h,int from,int x,int y){','static bool pull_step(const Hunt& h,int from,int x,int y){ if(distance_xy(x,y,h.x,h.y)>4)return false;')
key='bool population_mob_peel('
ai(key,'''bool admission_castend(block_list* src,block_list* dest){
 if(!admission_enabled() || !src || !dest || !pc_isdead(map_id2sd(dest->id)))return true;
 auto s=shells.find(src->id); if(s==shells.end())return true;
 auto* o=map_id2sd(s->second.account);
 return o && resurrection_safe(s->second,map_id2sd(dest->id),o);
}
'''.replace('!pc_isdead(map_id2sd(dest->id))','!map_id2sd(dest->id) || !pc_isdead(map_id2sd(dest->id))')+key)
key='skill->impl->castendNoDamageId( src, bl, skill_lv, tick, flag );'
inject('skill',key,'extern bool admission_castend(block_list*,block_list*); if(skill_id!=ALL_RESURRECTION || admission_castend(src,bl)) '+key)
key='//Clear target\n\tunit_set_target(ud, 0);'
inject('unit',key,'if(ud->attacktimer!=INVALID_TIMER && bl->type==BL_PC)ShowInfo("B_ATKCANCEL %lld %d %d %d\\n",(long long)gettick(),bl->id,ud->target,ud->attacktimer);\n'+key)
five_native.hooks=hooks
instrument=five_native.instrument
def observe(code):
    return instrument(code).replace('auto* ice=m->sc.getSCE','if(m->mob_id==1213 && distance_bl(m,own)<=12)trial::stop("high_orc",own->id,tick);\n    auto* ice=m->sc.getSCE')
five_native.instrument=observe
os.environ['BRAIN_FIVE']='1'
runpy.run_path(str(stage2/'build.py'),run_name='__main__')
