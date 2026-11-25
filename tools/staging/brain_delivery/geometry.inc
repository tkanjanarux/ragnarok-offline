// Disposable one-owner trial. The anchor still owns the survey grid.
static bool delivery_clear(const Hunt& h,int x,int y) {
    for(auto& p:h.rear_cells)
        if(distance_xy(x,y,p.first,p.second)<=2)return false;
    return true;
}
// A moving owner can enter an existing train. Leave an overlapping buffer only
// along edges which maintain or increase clearance from each affected cell.
static bool delivery_edge(const Hunt& h,int x,int y,int nx,int ny){
    for(auto& p:h.rear_cells){
        int after=distance_xy(nx,ny,p.first,p.second);
        if(after<=2 && after<distance_xy(x,y,p.first,p.second))return false;
    }
    return true;
}
// Rebooking a live train needs stronger evidence than reserving an empty dock.
static bool delivery_corridor(const Hunt& h,block_list* actor,int x,int y){
    walkpath_data path{};
    int cx=actor->x,cy=actor->y;
    if((cx!=x || cy!=y) && !path_search(&path,actor->m,cx,cy,x,y,0,CELL_CHKNOPASS))return false;
    for(int i=0;i<path.path_len;i++){
        int nx=cx+dirx[path.path[i]],ny=cy+diry[path.path[i]];
        if(!pull_cell(h,nx,ny) || !delivery_edge(h,cx,cy,nx,ny))return false;
        cx=nx;cy=ny;
    }
    return true;
}
static bool train_can_approach(const Hunt& h,map_session_data* puller,int x,int y){
    if(!delivery_corridor(h,puller,x,y))return false;
    for(int id:h.pack)if(auto* m=map_id2md(id)){
        if(m->target_id!=puller->id)continue;
        // Before the mob sees the dock it follows the puller. Check both
        // shortcuts, since validating only the puller's route misses corners.
        if(!delivery_corridor(h,m,puller->x,puller->y) || !delivery_corridor(h,m,x,y))return false;
    }
    return true;
}
static void delivery_plan(map_session_data* owner,Hunt& h,Shell* tank,Shell* wizard,mob_data* lead) {
    h.rear_cells={{owner->x,owner->y}};
    if(owner->ud.walktimer!=INVALID_TIMER){
        int px=owner->x,py=owner->y;
        const auto& path=owner->ud.walkpath;
        for(int i=path.path_pos;i<path.path_len;i++){
            px+=dirx[path.path[i]];py+=diry[path.path[i]];
            h.rear_cells.emplace_back(px,py);
        }
    }
    map_session_data* priest=nullptr;
    for(auto& [id,s]:shells)if(hunt_member(s,owner) && s.sd!=tank->sd){
        h.rear_cells.emplace_back(s.sd->x,s.sd->y);
        if(s.profile==5)priest=s.sd;
    }
    const int old=h.drop_x, old_y=h.drop_y;
    h.drop_x=h.drop_y=0;
    if(!wizard || !priest || pc_isdead(priest))return;
    auto valid=[&](int x,int y,int dx,int dy){
        int ex=x+3*dx,ey=y+3*dy;
        for(int i=-1;i<=3;i++){
            int px=x+i*dx,py=y+i*dy;
            if(!delivery_clear(h,px,py) || !pull_cell(h,px,py) || !map_getcell(owner->m,px,py,CELL_CHKPASS))return false;
        }
        return path_search_long(nullptr,owner->m,x,y,ex,ey,CELL_CHKWALL) &&
            check_distance_client_blxy(wizard->sd,x,y,skill_get_range2(wizard->sd,WZ_STORMGUST,1,true)) &&
            path_search_long(nullptr,owner->m,wizard->sd->x,wizard->sd->y,x,y,CELL_CHKWALL) &&
            battle_check_range(priest,wizard->sd,skill_get_range2(priest,AL_HEAL,1,true)) &&
            check_distance_client_blxy(priest,x,y,skill_get_range2(priest,AL_HEAL,1,true)) &&
            path_search_long(nullptr,owner->m,priest->x,priest->y,x,y,CELL_CHKWALL);
    };
    const bool approach=h.had_dock && !h.pack.empty() && (h.inbound || h.release_pack) &&
        distance_xy(tank->sd->x,tank->sd->y,h.x,h.y)<=16;
    if(old && valid(old,old_y,h.drop_dx,h.drop_dy) && (!approach || train_can_approach(h,tank->sd,old,old_y))){h.drop_x=old;h.drop_y=old_y;return;}
    // Once a train is in flight, do not flip its entrance to the opposite side.
    if(!h.pack.empty() && h.had_dock){
        if(old)ShowInfo("B_INVALID %lld %d %d %d %d %d %d\n",(long long)gettick(),old,old_y,owner->x,owner->y,tank->sd->x,tank->sd->y);
        // Rebook on the same flank only. A crossing owner retains the right
        // of way, including the uncompleted part of the owner's walk.
        if(owner->ud.walktimer==INVALID_TIMER){
            int best=INT_MAX,chosen_dx=0,chosen_dy=0;
            for(int direction=0;direction<8;direction++){
                const int dx=dirx[direction],dy=diry[direction];
                if(!approach && dx*h.drop_dx+dy*h.drop_dy<=0)continue;
                if(approach && dx*(tank->sd->x-owner->x)+dy*(tank->sd->y-owner->y)<0)continue;
                for(int extra:{6,7,5,8}){
                    int x=owner->x+extra*dx,y=owner->y+extra*dy;
                    int score=distance_xy(tank->sd->x,tank->sd->y,x,y)*2+abs(extra-6);
                    if(score>=best || !valid(x,y,dx,dy) || !delivery_corridor(h,tank->sd,x,y) ||
                       (approach && !train_can_approach(h,tank->sd,x,y)))continue;
                    bool train_clear=true;
                    for(int mid:h.pack)if(auto* m=map_id2md(mid))
                        if(m->target_id==tank->sd->id && !delivery_corridor(h,m,x,y)){train_clear=false;break;}
                    if(!train_clear)continue;
                    h.drop_x=x;h.drop_y=y;chosen_dx=dx;chosen_dy=dy;best=score;
                }
            }
            if(h.drop_x){
                h.drop_dx=chosen_dx;h.drop_dy=chosen_dy;
                h.ex=h.drop_x+6*chosen_dx;h.ey=h.drop_y+6*chosen_dy;
                ShowInfo("B_DOCK %lld %d %d %d %d %d %d\n",(long long)gettick(),owner->x,owner->y,h.drop_x,h.drop_y,chosen_dx,chosen_dy);
            }
        }
        return;
    }
    if(h.pack.empty())h.had_dock=false;
    int tx=lead?lead->x:tank->sd->x,ty=lead?lead->y:tank->sd->y;
    int best=INT_MAX;
    for(int d=0;d<8;d++)for(int reach:{6,5,7}){
        int dx=dirx[d],dy=diry[d],x=h.x+reach*dx,y=h.y+reach*dy;
        int score=distance_xy(tx,ty,x+3*dx,y+3*dy)*8+abs(6-reach);
        if(score>=best || !valid(x,y,dx,dy))continue;
        best=score;h.drop_x=x;h.drop_y=y;h.drop_dx=dx;h.drop_dy=dy;
    }
    if(h.drop_x){h.had_dock=true;h.ex=h.drop_x+6*h.drop_dx;h.ey=h.drop_y+6*h.drop_dy;}
    if(h.drop_x)ShowInfo("B_DOCK %lld %d %d %d %d %d %d\n",(long long)gettick(),owner->x,owner->y,h.drop_x,h.drop_y,h.drop_dx,h.drop_dy);
}

// Lower-bound arrival at the near edge of the damaging cells; usable only on
// a clear approach and for monsters actually chasing this puller.
static void delivery_window(Hunt& h,Shell* wizard,Shell* tank,t_tick now){
    h.approaching=0;h.pace=false;
    if(!wizard || !h.drop_x)return;
    auto* w=wizard->sd;
    const auto& u=w->ud;
    int state=0;
    t_tick starts=std::max(now,u.canact_tick)+skill_castfix(w,WZ_STORMGUST,1);
    if(u.skilltimer!=INVALID_TIMER && u.skill_id==WZ_STORMGUST &&
       u.skillx==h.drop_x && u.skilly==h.drop_y){
        const auto* t=get_timer(u.skilltimer);
        if(t){state=1;starts=t->tick;}
    }
    t_tick ends=starts+skill_get_time(WZ_STORMGUST,1);
    for(const auto& g:u.skillunits){
        if(!g || !g->alive_count || g->skill_id!=WZ_STORMGUST)continue;
        for(int i=0;i<g->unit_count;i++){
            if(g->unit[i].alive && g->unit[i].x==h.drop_x && g->unit[i].y==h.drop_y){
                state=2;starts=g->tick;ends=g->tick+g->limit;break;
            }
        }
    }
    int first=INT_MAX,last=0,nearest=0,n=0;
    for(int id:h.pack){
        auto* m=map_id2md(id);
        if(!m || m->target_id!=tank->sd->id ||
           !path_search_long(nullptr,w->m,m->x,m->y,h.drop_x,h.drop_y,CELL_CHKWALL))continue;
        int d=distance_xy(m->x,m->y,h.drop_x,h.drop_y);
        int eta=std::max(0,d-4)*int(m->status.speed);
        if(eta<first){first=eta;nearest=id;}
        last=std::max(last,eta);++n;
    }
    // An actual approaching train may trigger native spell selection early.
    // Never delay an emergency return in order to hit a predicted window.
    if(h.release_pack && n>=2 && ends>now+first && last<=ends-now)h.approaching=nearest;
    if(state==1 && n>=2 && h.release_pack && last<starts-now &&
       distance_xy(tank->sd->x,tank->sd->y,h.drop_x,h.drop_y)>5 &&
       tank->sd->battle_status.hp*100ULL>tank->sd->battle_status.max_hp*h.stop_hp &&
       !h.pressed && !h.hazard_near_train){
        // Yield only while the protected caster is genuinely casting and the
        // tail would otherwise beat it. Abandon pacing on contact.
        bool clear=true;
        for(int id:h.pack)if(auto* m=map_id2md(id))
            if(distance_bl(m,tank->sd)<=status_get_range(m)+2)clear=false;
        h.pace=clear;
    }
    if(h.last_window!=state || (n && now>=h.next_trace))
        ShowInfo("B_WINDOW %lld %d %d %d %d %d %d %lld %lld\n",(long long)now,h.drop_x,h.drop_y,state,n,n?first:-1,last,(long long)(starts-now),(long long)(ends-now));
    h.last_window=state;
}

// Recheck at commitment. A small ETA from distance alone says nothing about
// a mob which stopped walking or is following a tank away from the field.
static bool delivery_viable(const Hunt& h,map_session_data* wizard){
    auto* puller=map_id2sd(h.opener);
    if(!puller)return false;
    for(int id:h.pack){
        auto* m=map_id2md(id);
        if(!m || status_isdead(*m))continue;
        int d=distance_xy(m->x,m->y,h.drop_x,h.drop_y);
        if(d<=4)return true;
        if(!h.release_pack || m->target_id!=puller->id || m->sc.getSCE(SC_FREEZE) ||
           m->ud.walktimer==INVALID_TIMER || distance_xy(puller->x,puller->y,h.drop_x,h.drop_y)>4 ||
           !path_search_long(nullptr,wizard->m,m->x,m->y,h.drop_x,h.drop_y,CELL_CHKWALL))continue;
        if(distance_xy(m->ud.to_x,m->ud.to_y,h.drop_x,h.drop_y)<=4)return true;
    }
    return false;
}

// For an invalidated handoff, find one lateral casting position reachable
// without stepping through the train. The owner and healer remain native.
static bool delivery_cast_position(map_session_data* w,const Hunt& h,map_session_data* owner,int& fx,int& fy){
    map_session_data* support=nullptr;
    for(auto& [id,s]:shells)if(hunt_member(s,owner) && s.profile==5)support=s.sd;
    if(!support || pc_isdead(support))return false;
    int dock_x=owner->x+6*h.drop_dx,dock_y=owner->y+6*h.drop_dy;
    int best=INT_MAX;
    for(int side:{1,-1})for(int lateral:{3,4,2,5,6})for(int back:{0,1,2,3}){
        int x=owner->x-side*h.drop_dy*lateral-back*h.drop_dx;
        int y=owner->y+side*h.drop_dx*lateral-back*h.drop_dy;
        if(!pull_cell(h,x,y) || !check_distance_client_xy(x,y,dock_x,dock_y,skill_get_range2(w,WZ_STORMGUST,1,true)) ||
           !check_distance_client_blxy(support,x,y,skill_get_range2(support,AL_HEAL,1,true)) ||
           !path_search_long(nullptr,w->m,support->x,support->y,x,y,CELL_CHKWALL) ||
           !path_search_long(nullptr,w->m,x,y,dock_x,dock_y,CELL_CHKWALL))continue;
        walkpath_data route{};
        if((w->x!=x || w->y!=y) && !path_search(&route,w->m,w->x,w->y,x,y,0,CELL_CHKNOPASS))continue;
        int cx=w->x,cy=w->y;
        bool safe=true;
        for(int i=0;i<=route.path_len && safe;i++){
            if(i){cx+=dirx[route.path[i-1]];cy+=diry[route.path[i-1]];}
            if(!pull_cell(h,cx,cy)){safe=false;break;}
            for(int id:h.pack)if(auto* m=map_id2md(id))
                if(distance_xy(m->x,m->y,cx,cy)<=status_get_range(m)+2){safe=false;break;}
        }
        if(safe && route.path_len<best){best=route.path_len;fx=x;fy=y;}
    }
    return best!=INT_MAX;
}
