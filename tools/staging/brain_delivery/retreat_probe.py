"""Isolated regression for interaction between delivery and native emergency retreat.

Use DELIVERY_CASE=retreat_before or retreat_after. Does not enable new combat
orders, resume a stopped team, or change other builder entry points.
"""
import runpy
import sys
from pathlib import Path

here=Path(__file__).resolve().parent
sys.path.insert(0,str(here.parent/'brain_stage2'))
import five_native


def after(key,source):
    five_native.hooks+="\nchanges['population_engine/minimal'].append("+repr((key,key+source))+")\n"


key='if(h.release_pack || !best){'
after(key,'''
        const char* probe=std::getenv("DELIVERY_CASE");
        static bool fired=false;
        if(!fired && probe && !strncmp(probe,"retreat_",8) && h.pack.size()>=2 && h.drop_x &&
           distance_xy(tank->sd->x,tank->sd->y,h.x,h.y)>9){
            fired=true;
            ShowInfo("B_FAULT %lld retreat %d %d %zu\\n",(long long)now,tank->sd->x,tank->sd->y,h.pack.size());
            team_retreat(owner,h,"isolated withdrawal probe");
            return;
        }
''')
key='static bool walk_pull(map_session_data* sd,const Hunt& h,int x,int y,int stride){'
after(key,'''
    const char* probe=std::getenv("DELIVERY_CASE");
    if(h.retreat && probe && !strcmp(probe,"retreat_after") && !h.pack.empty()){
        // Never substitute the normal drop point or enter the owner's cell
        // with an engaged train. Seek a covered exit on the puller's side.
        map_session_data* nurse=nullptr;
        for(const auto& [id,s]:shells)if(s.profile==5 && s.sd && s.sd->status.party_id==sd->status.party_id)nurse=s.sd;
        if(!nurse || pc_isdead(nurse))return false;
        const int heal_range=skill_get_range2(nurse,AL_HEAL,1,true);
        int best=INT_MAX,bx=0,by=0;
        for(int dir=0;dir<8;dir++)for(int dist:{5,6,7}){
            int nx=nurse->x+dist*dirx[dir],ny=nurse->y+dist*diry[dir];
            if(distance_xy(nx,ny,h.drop_x,h.drop_y)<3 || !delivery_clear(h,nx,ny) ||
               !check_distance_client_blxy(nurse,nx,ny,heal_range) || !map_getcell(sd->m,nx,ny,CELL_CHKPASS) ||
               !path_search_long(nullptr,sd->m,nurse->x,nurse->y,nx,ny,CELL_CHKWALL))continue;
            int cost=distance_xy(sd->x,sd->y,nx,ny);
            if(cost>=best || !train_can_approach(h,sd,nx,ny))continue;
            best=cost;bx=nx;by=ny;
        }
        if(best==INT_MAX)return false;
        x=bx;y=by;
    }
''')
runpy.run_path(str(here/'build.py'),run_name='__main__')
