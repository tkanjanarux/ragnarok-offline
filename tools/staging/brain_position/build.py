"""Instrument the five-member native fixture, with a single position treatment."""
import os,runpy,sys
from pathlib import Path
root=Path(__file__).resolve().parent
stage2=root.parent/'brain_stage2'
sys.path.insert(0,str(stage2))
import five_native
work=Path(sys.argv[2])
(work/'trip_guard.hpp').write_bytes((root.parent/'brain_stage3/trip_guard.hpp').read_bytes())
def patch(file,old,new):
    five_native.hooks+='\nchanges['+repr(file)+'].append('+repr((old,new))+')\n'
def ai(old,new):patch('population_engine/minimal',old,new)
for unit in ('status','population_engine/minimal'):
    key='#include <common/showmsg.hpp>'
    patch(unit,key,key+'\n#include "trip_guard.hpp"')
key='status->hp-= hp;'
patch('status',key,'trial::hit(target->id,status->hp,status->max_hp,hp,gettick());\n'+key)
# The calm-room comparison and the emergency trial both forbid re-raising after the latch.
key='if(name=="resurrection") {'
ai(key,key+' if(trial::stopped)continue;')
key='skill->impl->castendNoDamageId( src, bl, skill_lv, tick, flag );'
patch('skill','#include <common/showmsg.hpp>','#include <common/showmsg.hpp>\n#include "trip_guard.hpp"')
patch('skill',key,'if(skill_id!=ALL_RESURRECTION || !trial::stopped) '+key)
key='void update_team(map_session_data* owner,Hunt& h) {'
ai(key,key+'''
    trial::armed=true;
    if(FILE* f=std::fopen("artifacts/trial.stop","r")){std::fclose(f);trial::stop("manual",owner->id,gettick());}
    if(trial::stopped && !trial::regrouped){
        team_retreat(owner,h,"position trial stop");trial::regrouped=true;
        ShowInfo("B_REGROUP %lld %d\\n",(long long)gettick(),owner->id);
    }''')
key='bool support_party(Shell&'
position=(root.parent/'brain_admission/position.inc').read_text().split('static bool peel_allowed')[0]
ai(key,position+'\n'+key)
key='if(shell.profile==5 && farming){'
ai(key,key+'''auto* wizard=map_id2sd(95000002);
        if(std::getenv("CAMP_POSITION") && wizard && !pc_isdead(wizard) &&
           (!battle_check_range(sd,wizard,8) || !battle_check_range(sd,owner,8)))
            return camp_cover(shell,owner);''')
key='if(distance_bl(sd,owner)>3 && sd->ud.walktimer==INVALID_TIMER)'
ai(key,'if(std::getenv("CAMP_POSITION"))camp_cover(shell,owner); else '+key)
for key in ('static bool pull_cell(const Hunt& h,int x,int y){','static bool pull_step(const Hunt& h,int from,int x,int y){'):
    ai(key,key+' if(h.radius==6 && distance_xy(x,y,h.x,h.y)>4)return false;')
old=five_native.instrument
def instrument(src):
    src=old(src)
    key='auto& b=a->battle_status;'
    return src.replace(key,key+'''
        static std::set<int> printed;
        if(printed.insert(a->id).second){
           ShowInfo("B_BUILD %lld %d %d %d %d %d %d %d %d %d %d\\n",now,a->id,a->status.base_level,a->status.job_level,a->status.class_,b.hp,b.max_hp,b.sp,b.max_sp,pc_checkskill(a,AL_HEAL),pc_checkskill(a,PR_KYRIE));
           for(int i=0;i<MAX_INVENTORY;i++){
               auto& it=a->inventory.u.items_inventory[i];
               if(it.nameid && it.equip)ShowInfo("B_GEAR %lld %d %u %u %d %u %u %u %u\\n",now,a->id,(unsigned)it.nameid,(unsigned)it.equip,(int)it.refine,(unsigned)it.card[0],(unsigned)it.card[1],(unsigned)it.card[2],(unsigned)it.card[3]);
           }
        }''')
five_native.instrument=instrument
os.environ['BRAIN_FIVE']='1'
runpy.run_path(str(stage2/'build.py'),run_name='__main__')
