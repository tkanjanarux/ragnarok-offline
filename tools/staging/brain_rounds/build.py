"""Build only the isolated five-companion round experiment over delivery v10."""
import runpy
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
sys.path.insert(0, str(here.parent / "brain_stage2"))
import five_native


def patch(old, new):
    five_native.hooks += "\nchanges['population_engine/minimal'].append(" + repr((old, new)) + ")\n"


key = 'bool retreat=false, release_pack=false, outbound_train=false;'
patch(key, key + '''
    enum Round { Ready, Pull, Clear, Withdraw } round=Ready;
    std::set<int> outstanding;
    int camp_add=0;
''')
key = 'if(hp<h.retreat_hp || (h.mode==TeamMode::boss'
patch(key, key.replace('hp<h.retreat_hp', '(h.mode!=TeamMode::mob && hp<h.retreat_hp)'))
key = 'if (h.missed.count(mob->id)) return 0;'
patch(key, 'if (h.missed.count(mob->id) && !team_victim(mob,owner)) return 0;')
key = 'const bool at_camp=distance_xy'
patch(key, '''
    // Remember live followers even if the native escort gives up on tagging them.
    for(auto it=h.outstanding.begin();it!=h.outstanding.end();){
        auto* m=map_id2md(*it);
        if(!m || !m->prev || m->m!=owner->m || distance_xy(m->x,m->y,h.x,h.y)>h.radius+3 || status_isdead(*m) || !unclaimed(owner,m) ||
           (!team_victim(m,owner) && !h.pack.count(*it) && distance_xy(m->x,m->y,h.x,h.y)>7))
            it=h.outstanding.erase(it);
        else ++it;
    }
    h.outstanding.insert(h.pack.begin(),h.pack.end());
    for(int id:h.outstanding)h.pack.insert(id);
    '''+key)
key='if(reason){\n        h.inbound'
patch(key, (here/'admission.inc').read_text()+'\n    '+key)
key='if(!was_released && ready && h.pack.size()>1'
patch(key, '''if(h.round==Hunt::Withdraw){
            h.wait_for_area_until=0;
            if(together)h.opened=true;
        }
        '''+key.replace('if(!was','if(h.round!=Hunt::Withdraw && !was'))
key='if(tank && !h.rescue_ally && !h.pressed'
patch(key,key.replace('if(tank','if(h.round!=Hunt::Withdraw && tank'))
key='if(!escorting && h.mode==TeamMode::mob && hunter)cover_stray();'
patch(key,key+'''
            if(h.mode==TeamMode::mob && uses_ground_build(shell) && h.camp_add && !h.approaching &&
               !(h.release_pack && h.pack.size()>1 && delivery_viable(h,sd))){
                auto* m=map_id2md(h.camp_add);
                if(m && distance_xy(m->x,m->y,h.x,h.y)<=7 && battle_check_range(sd,m,8) &&
                   (team_victim(m,owner) || (h.hunter_hit_target==m->id && h.hunter_hit_damage>0)))
                    target=m;
            }''')
key='if(cast_build_ground(shell,target))return true;'
patch(key,'''const bool camp_single=hunt!=hunts.end() && target->id==hunt->second.camp_add && !hunt->second.approaching &&
            !(hunt->second.release_pack && hunt->second.pack.size()>1 && (hunt->second.outbound_train || delivery_viable(hunt->second,sd)));
        if(camp_single){
            auto* m=static_cast<mob_data*>(target);
            if(!team_victim(m,owner) && !(hunt->second.hunter_hit_target==m->id && hunt->second.hunter_hit_damage>0))return true;
        }
        if(!camp_single && cast_build_ground(shell,target))return true;''')
key='for(const auto& skill:shell.policy.skills){\n            if(skill=="concentration"'
patch(key,'''if(hunt!=hunts.end() && hunt->second.camp_add==target->id &&
           !team_victim(static_cast<mob_data*>(target),owner)){
            if(std::find(shell.policy.skills.begin(),shell.policy.skills.end(),"double")!=shell.policy.skills.end())
                cast_skill(shell,target,AC_DOUBLE,1);
            return true;
        }
        '''+key)
key='bool knight_guard_for_mob='
patch(key,'''if(uses_ground_build(it->second) && h.camp_add==mob->id && !team_victim(mob,owner) &&
               !(h.hunter_hit_target==mob->id && h.hunter_hit_damage>0))return false;
            if(uses_ground_build(it->second) && h.camp_add==mob->id && distance_xy(h.x,h.y,mob->x,mob->y)<=7 &&
               (team_victim(mob,owner) || (h.hunter_hit_target==mob->id && h.hunter_hit_damage>0)) &&
               !mob->master_id && mob->get_bosstype()==BOSSTYPE_NONE)return true;
            '''+key)
key='if(!camp_single && cast_build_ground(shell,target))return true;'
patch(key,key+"""
        if(hunt!=hunts.end() && hunt->second.release_pack && hunt->second.outbound_train &&
           hunt->second.pack.size()>1 && target->id==hunt->second.camp_add &&
           !delivery_viable(hunt->second,sd))return true;""")
runpy.run_path(str(here.parent/'brain_delivery/build.py'),run_name='__main__')
