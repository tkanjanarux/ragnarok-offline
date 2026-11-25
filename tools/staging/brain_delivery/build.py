"""Build a disposable delivery-map server with the existing five-character fixture."""
import runpy
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
sys.path.insert(0, str(here.parent / 'brain_stage2'))
import five_native


def change(old, new):
    five_native.hooks += "\nchanges['population_engine/minimal'].append(" + repr((old, new)) + ")\n"


key = 'int front_x=0,front_y=0;'
change(key, key + '\n    bool had_dock=false,pace=false; int ex=0,ey=0; int last_window=-1,approaching=0; int drop_x=0,drop_y=0,drop_dx=0,drop_dy=0; std::vector<std::pair<int,int>> rear_cells;')
key = 'void update_team(map_session_data* owner,Hunt& h)'
change(key, (here/'geometry.inc').read_text()+'\n'+key)
key = '    // Defend the camp'
change(key, '''    delivery_plan(owner,h,tank,wizard,best);
    if(wizard && wizard->sd->ud.skilltimer!=INVALID_TIMER && wizard->sd->ud.skill_id==WZ_STORMGUST &&
       (wizard->sd->ud.skillx!=h.drop_x || wizard->sd->ud.skilly!=h.drop_y ||
        std::none_of(h.pack.begin(),h.pack.end(),[](int id){
            auto* m=map_id2md(id);return m && m->prev && !status_isdead(*m);
        })))unit_skillcastcancel(wizard->sd,0);
    if(!h.drop_x){
        best=nullptr;h.tour.clear();h.approaching=0;

    }
    delivery_window(h,wizard,tank,now);
'''+key)
key = 'int d=distance_xy(h.x,h.y,mob->x,mob->y);\n        if(d>6)'
change(key, key.replace('h.x,h.y','h.drop_x,h.drop_y'))
for old in ('distance_xy(mob->x,mob->y,h.x,h.y);\n            if(dist<nearest)',
            'distance_xy(mob->x,mob->y,h.x,h.y)<=7)++together',
            'const int tank_distance=distance_xy(tank->sd->x,tank->sd->y,h.x,h.y)'):
    change(old,old.replace('h.x,h.y','h.drop_x,h.drop_y'))
key = 'if(distance_xy(x,y,encounter->second.x,encounter->second.y)<=7){'
change(key, '''if(id==WZ_STORMGUST){
   if(!encounter->second.drop_x)return skip("delivery-unavailable");
   x=encounter->second.drop_x;y=encounter->second.drop_y;
  }else '''+key)
change('if(blocked && b!=B::pillar){','if(blocked && b!=B::pillar && id!=WZ_STORMGUST){')
key='if(tank && h.mode==TeamMode::mob && shell.skills'
change(key,'''if(tank && h.mode==TeamMode::mob && (!h.drop_x || h.pace)){
                unit_stop_attack(sd);
                const bool escape=!h.drop_x && h.had_dock && !h.pack.empty() &&
                    distance_xy(sd->x,sd->y,h.ex,h.ey)>1 && pull_cell(h,h.ex,h.ey) &&
                    delivery_clear(h,h.ex,h.ey);
                if(escape){
                    if(sd->ud.walktimer==INVALID_TIMER)walk_pull(sd,h,h.ex,h.ey,3);
                }else if(sd->ud.walktimer!=INVALID_TIMER)unit_stop_walking(sd,USW_FIXPOS|USW_FORCE_STOP);
                return true;
            }
            '''+key)
key='if(form && distance_xy(sd->x,sd->y,fx,fy)'
change(key,'''if(h.mode==TeamMode::mob && (h.drop_x || h.had_dock)){
                if(tank && h.drop_x && h.release_pack && !h.pack.empty()){
                    fx=h.drop_x;fy=h.drop_y;form=true;
                }else if(rear){
                    // Keep the current ready casting position when it satisfies the meeting.
                    fx=sd->x;fy=sd->y;form=false;
                    if(!h.drop_x && h.had_dock && owner->ud.walktimer==INVALID_TIMER &&
                       (owner->x!=h.x || owner->y!=h.y))
                        form=delivery_cast_position(sd,h,owner,fx,fy);
                }
            }
            '''+key)
key='if(!pull_step(h,at,nx,ny) || parent[next]>=0'
change(key,'''if(!map_getcell(sd->m,nx,ny,CELL_CHKPASS) || !map_getcell(sd->m,cx,ny,CELL_CHKPASS) ||
               !map_getcell(sd->m,nx,cy,CELL_CHKPASS) ||
               (!h.pack.empty() && !delivery_edge(h,cx,cy,nx,ny)))continue;
            '''+key)
key='if(h.hold_train || start<0 || goal<0'
change(key,'''if(h.release_pack && !h.pack.empty() && sd->id==h.opener && h.drop_x && x==h.x && y==h.y){
        x=h.drop_x;y=h.drop_y;goal=h.route_index(x,y);
    }
    '''+key)
key='if(h.hold_train || !pull_step(h,from,x,y))'
change(key,'if(h.hold_train || !pull_step(h,from,x,y) || (!h.pack.empty() && !delivery_edge(h,x-dirx[path.path[i]],y-diry[path.path[i]],x,y)))')
key='if(!can_spend_sp(shell,id,lv))return skip("SP-or-reserve");'
change(key, """if(id==WZ_STORMGUST && encounter!=hunts.end() && encounter->second.mode==TeamMode::mob){
  auto& h=encounter->second;
  if(!h.drop_x || !delivery_viable(h,sd))return skip("no-delivery-at-impact");
 }
 """+key)
key='if(!threatened && (nearby<2'
change(key, 'if(h.approaching && !h.camp_target)h.camp_target=h.approaching;\n    '+key.replace('if(!threatened','if(!h.approaching && !threatened'))
key='(distance_xy(h.x,h.y,mob->x,mob->y)<=7 &&\n                   (h.pack'
change(key,key.replace('h.x,h.y','h.drop_x,h.drop_y'))
key='    delivery_plan(owner,h,tank,wizard,best);'
change(key, """
    static bool injected=false;
    const char* probe=std::getenv("DELIVERY_CASE");
    if(!injected && probe && !strcmp(probe,"lane") && h.drop_x && !h.pack.empty()){
        const int x=h.drop_x+2*h.drop_dx,y=h.drop_y+2*h.drop_dy;
        for(int offset=-2;offset<=2;offset++){
            map_setcell(owner->m,x-offset*h.drop_dy,y+offset*h.drop_dx,CELL_WALKABLE,false);
            map_setcell(owner->m,x-offset*h.drop_dy,y+offset*h.drop_dx,CELL_SHOOTABLE,false);
        }
        injected=true;ShowInfo("B_FAULT %lld lane %d %d\\n",(long long)now,x,y);
    }
    if(!injected && wizard && probe && !strcmp(probe,"late") && h.pack.size()>=2){
        for(const auto& g:wizard->sd->ud.skillunits)if(g && g->skill_id==WZ_STORMGUST && g->alive_count && g->tick+g->limit-now<1800){
            auto* m=map_id2md(*h.pack.rbegin());
            int x=h.drop_x+15*h.drop_dx,y=h.drop_y+15*h.drop_dy;
            if(m && pull_cell(h,x,y) && unit_movepos(m,x,y,0,false)){
                injected=true;ShowInfo("B_FAULT %lld late %d %d %d %d\\n",(long long)now,m->id,x,y,g->group_id);
            }
            break;
        }
    }
    if(!injected && wizard && probe && !strcmp(probe,"interrupt") &&
       wizard->sd->ud.skill_id==WZ_STORMGUST && wizard->sd->ud.skilltimer!=INVALID_TIMER){
        unit_skillcastcancel(wizard->sd,0);injected=true;
        ShowInfo("B_FAULT %lld interrupt %d\\n",(long long)now,wizard->sd->ud.skilltimer);
    }
"""+key)
runpy.run_path(str(here.parent/'brain_position/build.py'), run_name='__main__')
